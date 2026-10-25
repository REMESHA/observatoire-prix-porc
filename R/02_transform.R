# =============================================================================
# 02_transform.R — TRANSFORM
# Lit les JSON bruts, harmonise les formats et les unités, puis applique des
# contrôles qualité. Chaque anomalie est tracée dans une table dédiée.
#
# Sévérité des anomalies :
#   - "bloquant" : la ligne est écartée (valeur illisible, unité inconnue...)
#   - "alerte"   : la ligne est conservée mais signalée (variation brutale...)
# =============================================================================

library(dplyr)
library(tidyr)
library(jsonlite)

lire_json <- function(fichiers) {
  bind_rows(lapply(fichiers, \(f) {
    d <- fromJSON(f, simplifyVector = TRUE)
    if (length(d) == 0) return(NULL)
    d$fichier_source <- basename(f)
    as_tibble(d)
  }))
}

nouvelle_anomalie <- function(df, type, severite, detail) {
  if (nrow(df) == 0) return(NULL)
  tibble(
    source     = df$source,
    code_pays  = df$code_pays,
    serie      = df$serie,
    date       = as.Date(df$date),
    valeur     = df$valeur,
    type       = type,
    severite   = severite,
    detail     = detail
  )
}

# ---------------------------------------------------------------------------
# Prix hebdomadaires
# ---------------------------------------------------------------------------
transformer_prix <- function(fichiers, cfg = CONFIG) {
  brut <- lire_json(fichiers)
  log_info("Prix : ", nrow(brut), " lignes brutes lues")

  prix <- brut |>
    transmute(
      code_pays    = memberStateCode,
      nom_pays     = memberStateName,
      classe       = pigClass,
      date_debut   = parse_date_fr(beginDate),
      date_fin     = parse_date_fr(endDate),
      semaine_api  = as.integer(weekNumber),
      prix_source  = price,
      unite_source = unit,
      valeur_brute = parse_prix(price),
      fichier_source
    ) |>
    mutate(
      annee_iso   = as.integer(format(date_debut, "%G")),
      semaine_iso = as.integer(format(date_debut, "%V")),
      # Harmonisation : carcasses en €/kg, porcelets en €/tête
      unite = case_when(
        unite_source == "100 KG" ~ "EUR/kg carcasse",
        unite_source == "P"      ~ "EUR/tete",
        TRUE                     ~ NA_character_
      ),
      prix = case_when(
        unite_source == "100 KG" ~ valeur_brute / 100,
        unite_source == "P"      ~ valeur_brute,
        TRUE                     ~ NA_real_
      )
    )

  anomalies <- list()
  vue_qc <- function(d) mutate(d, source = "prix", serie = classe,
                               date = date_debut, valeur = valeur_brute)

  # 1. Valeurs illisibles, nulles ou négatives -> bloquant
  ko_valeur <- prix |> filter(is.na(valeur_brute) | valeur_brute <= 0) |> vue_qc()
  anomalies$valeur <- nouvelle_anomalie(ko_valeur, "valeur_invalide", "bloquant",
                                        paste("Prix source :", ko_valeur$prix_source))

  # 2. Unité inattendue -> bloquant
  ko_unite <- prix |> filter(is.na(unite)) |> vue_qc()
  anomalies$unite <- nouvelle_anomalie(ko_unite, "unite_inconnue", "bloquant",
                                       paste("Unité source :", ko_unite$unite_source))

  # 3. Date illisible -> bloquant
  ko_date <- prix |> filter(is.na(date_debut)) |> vue_qc()
  anomalies$date <- nouvelle_anomalie(ko_date, "date_invalide", "bloquant",
                                      "Date de début de semaine illisible")

  prix <- prix |> filter(!is.na(prix), !is.na(date_debut))

  # 4. Doublons sur la clé (pays, classe, semaine).
  # Les doublons à valeur identique sont attendus (recouvrement volontaire des
  # requêtes annuelles ; l'API publie aussi la semaine de fin d'année à la fois
  # en semaine 53 et en semaine 1) : ils sont supprimés sans alerte.
  # Des valeurs différentes pour une même semaine signalent un conflit.
  conflits <- prix |>
    group_by(code_pays, classe, date_debut) |>
    filter(n() > 1, n_distinct(valeur_brute) > 1) |>
    summarise(valeurs = paste(unique(prix_source), collapse = " / "), .groups = "drop")
  if (nrow(conflits) > 0) {
    d <- conflits |> mutate(source = "prix", serie = classe, date = date_debut,
                            valeur = NA_real_)
    anomalies$doublons <- nouvelle_anomalie(
      d, "doublon_conflictuel", "alerte",
      paste("Valeurs différentes pour la même semaine :", d$valeurs,
            "— valeur du fichier le plus récent conservée"))
  }
  prix <- prix |>
    arrange(code_pays, classe, date_debut, desc(fichier_source)) |>
    distinct(code_pays, classe, date_debut, .keep_all = TRUE)

  # 5. Variations hebdomadaires brutales et valeurs atypiques (par série)
  prix <- prix |>
    arrange(code_pays, classe, date_debut) |>
    group_by(code_pays, classe) |>
    mutate(
      variation_hebdo = prix / lag(prix) - 1,
      ecart_jours     = as.numeric(date_debut - lag(date_debut)),
      z_robuste       = (prix - median(prix)) / (mad(prix) + 1e-9)
    ) |>
    ungroup()

  brutal <- prix |> filter(abs(variation_hebdo) > cfg$seuil_variation_hebdo) |> vue_qc()
  anomalies$variation <- nouvelle_anomalie(
    brutal, "variation_brutale", "alerte",
    sprintf("Variation sur une semaine : %+.1f %%", 100 * brutal$variation_hebdo))

  atypique <- prix |> filter(abs(z_robuste) > cfg$seuil_z_robuste) |> vue_qc()
  anomalies$atypique <- nouvelle_anomalie(
    atypique, "valeur_atypique", "alerte",
    sprintf("Score z robuste : %.1f", atypique$z_robuste))

  # 6. Semaines manquantes dans une série (écart > 7 jours)
  trou <- prix |> filter(ecart_jours > 7) |> vue_qc()
  anomalies$trous <- nouvelle_anomalie(
    trou, "semaines_manquantes", "alerte",
    sprintf("%d semaine(s) manquante(s) avant cette date", trou$ecart_jours / 7 - 1))

  prix <- prix |> select(-ecart_jours, -z_robuste)

  list(donnees = prix, anomalies = bind_rows(anomalies))
}

# ---------------------------------------------------------------------------
# Production mensuelle (abattages)
# Unités renvoyées par l'API : tonnes = milliers de tonnes équivalent carcasse,
# heads = milliers de têtes (vérifié : tonnes ≈ heads × kgPerHead / 1000).
# ---------------------------------------------------------------------------
transformer_production <- function(fichiers, cfg = CONFIG) {
  brut <- lire_json(fichiers)
  log_info("Production : ", nrow(brut), " lignes brutes lues")

  prod <- brut |>
    transmute(
      code_pays       = memberStateCode,
      nom_pays        = memberStateName,
      annee           = as.integer(year),
      mois            = mois_en_num(month),
      production_kt   = as.numeric(tonnes),
      abattages_milliers_tetes    = as.numeric(heads),
      poids_moyen_kg  = as.numeric(kgPerHead),
      fichier_source
    ) |>
    mutate(date_mois = as.Date(sprintf("%d-%02d-01", annee, mois)))

  anomalies <- list()
  vue_qc <- function(d) mutate(d, source = "production", serie = "production_kt",
                               date = date_mois, valeur = production_kt)

  ko <- prod |> filter(is.na(mois) | is.na(production_kt) | production_kt < 0) |> vue_qc()
  anomalies$valeur <- nouvelle_anomalie(ko, "valeur_invalide", "bloquant",
                                        "Mois ou production illisible")
  prod <- prod |> filter(!is.na(mois), !is.na(production_kt), production_kt >= 0)

  prod <- prod |>
    arrange(code_pays, date_mois, fichier_source) |>
    distinct(code_pays, date_mois, .keep_all = TRUE)

  # Cohérence interne : production ≈ têtes × poids moyen (tolérance 3 %)
  incoherent <- prod |>
    filter(!is.na(abattages_milliers_tetes), !is.na(poids_moyen_kg), abattages_milliers_tetes > 0) |>
    mutate(attendu = abattages_milliers_tetes * poids_moyen_kg / 1000,
           ecart   = production_kt / attendu - 1) |>
    filter(abs(ecart) > 0.03) |>
    vue_qc()
  anomalies$coherence <- nouvelle_anomalie(
    incoherent, "incoherence_interne", "alerte",
    sprintf("Production vs têtes × poids : écart %+.1f %%", 100 * incoherent$ecart))

  list(donnees = prod, anomalies = bind_rows(anomalies))
}

transform <- function(fichiers, cfg = CONFIG, run_id = NA_character_) {
  p  <- transformer_prix(fichiers$prix, cfg)
  pr <- transformer_production(fichiers$production, cfg)

  anomalies <- bind_rows(p$anomalies, pr$anomalies) |>
    mutate(run_id = run_id, .before = 1)

  # Rapport qualité lisible (CSV) en plus de la table en base
  readr::write_csv(anomalies, file.path(cfg$dir_qc, "anomalies_derniere_execution.csv"))
  resume <- anomalies |> count(source, type, severite, name = "n")
  readr::write_csv(resume, file.path(cfg$dir_qc, "resume_qualite.csv"))

  log_info("Contrôles qualité : ", nrow(anomalies), " anomalie(s) — ",
           sum(anomalies$severite == "bloquant"), " bloquante(s)")

  list(prix = p$donnees, production = pr$donnees, anomalies = anomalies)
}
