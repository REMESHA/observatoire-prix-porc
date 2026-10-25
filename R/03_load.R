# =============================================================================
# 03_load.R — LOAD
# Charge les données transformées dans une base DuckDB (schéma en étoile),
# de façon idempotente, puis exporte les tables pour Power BI.
# =============================================================================

library(DBI)
library(duckdb)
library(dplyr)

connexion <- function(cfg = CONFIG) {
  suppressMessages(dbConnect(duckdb::duckdb(), dbdir = cfg$db_path))
}

# Exécute un fichier .sql contenant plusieurs instructions
executer_sql <- function(con, fichier) {
  lignes <- readLines(fichier, warn = FALSE, encoding = "UTF-8")
  lignes <- sub("--.*$", "", lignes)                    # retire les commentaires
  instructions <- strsplit(paste(lignes, collapse = "\n"), ";")[[1]]
  instructions <- trimws(instructions)
  for (sql in instructions[nzchar(instructions)]) dbExecute(con, sql)
  invisible(length(instructions))
}

# Insère ou remplace des lignes à partir d'une table de transit (staging)
upsert <- function(con, table, df, cles) {
  stg <- paste0("stg_", table)
  dbWriteTable(con, stg, as.data.frame(df), temporary = TRUE, overwrite = TRUE)

  jointure <- paste(sprintf("s.%1$s = f.%1$s", cles), collapse = " AND ")
  n_nouveaux <- dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n FROM %s s LEFT JOIN %s f ON %s WHERE f.%s IS NULL",
    stg, table, jointure, cles[1]))$n

  colonnes <- paste(names(df), collapse = ", ")
  dbExecute(con, sprintf("INSERT OR REPLACE INTO %s (%s) SELECT %s FROM %s",
                         table, colonnes, colonnes, stg))
  dbExecute(con, paste("DROP TABLE", stg))
  list(n_charges = nrow(df), n_nouveaux = as.integer(n_nouveaux))
}

construire_dim_date <- function(debut, fin) {
  jours <- seq(as.Date(debut), as.Date(fin), by = "day")
  noms_mois <- c("janvier", "février", "mars", "avril", "mai", "juin", "juillet",
                 "août", "septembre", "octobre", "novembre", "décembre")
  mois <- as.integer(format(jours, "%m"))
  tibble(
    date          = jours,
    annee         = as.integer(format(jours, "%Y")),
    trimestre     = (mois - 1L) %/% 3L + 1L,
    mois          = mois,
    nom_mois      = noms_mois[mois],
    annee_mois    = format(jours, "%Y-%m"),
    annee_iso     = as.integer(format(jours, "%G")),
    semaine_iso   = as.integer(format(jours, "%V")),
    debut_semaine = jours - (as.integer(format(jours, "%u")) - 1L),
    debut_mois    = as.Date(format(jours, "%Y-%m-01"))
  )
}

DIM_CLASSE <- tibble(
  classe          = c("S", "E", "R", "Piglet"),
  libelle         = c("Classe S (très maigre)", "Classe E (référence)",
                      "Classe R", "Porcelet"),
  unite           = c(rep("EUR/kg carcasse", 3), "EUR/tete"),
  ordre_affichage = 1:4
)

load <- function(donnees, cfg = CONFIG, run_id) {
  con <- connexion(cfg)
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

  executer_sql(con, file.path(cfg$dir_sql, "01_schema.sql"))
  horodatage <- Sys.time()

  res <- dbWithTransaction(con, {
    # --- Dimensions ---
    pays <- bind_rows(
      distinct(donnees$prix, code_pays, nom_pays),
      distinct(donnees$production, code_pays, nom_pays)
    ) |>
      distinct(code_pays, .keep_all = TRUE) |>
      mutate(est_moyenne_ue = code_pays == "EU",
             est_agregat    = grepl("^EU", code_pays))
    upsert(con, "dim_pays", pays, "code_pays")
    upsert(con, "dim_classe", DIM_CLASSE, "classe")

    debut <- min(donnees$prix$date_debut, donnees$production$date_mois)
    fin   <- as.Date(sprintf("%d-12-31", as.integer(format(Sys.Date(), "%Y"))))
    dbExecute(con, "DELETE FROM dim_date")
    dbWriteTable(con, "dim_date", as.data.frame(construire_dim_date(debut, fin)),
                 append = TRUE)

    # --- Faits ---
    faits_prix <- donnees$prix |>
      transmute(code_pays, classe, date_debut, date_fin, annee_iso, semaine_iso,
                prix, unite, variation_hebdo, prix_source, fichier_source,
                run_id = run_id, charge_le = horodatage)
    r_prix <- upsert(con, "fait_prix_hebdo", faits_prix,
                     c("code_pays", "classe", "date_debut"))

    faits_prod <- donnees$production |>
      transmute(code_pays, date_mois, annee, mois, production_kt,
                abattages_milliers_tetes, poids_moyen_kg, fichier_source,
                run_id = run_id, charge_le = horodatage)
    r_prod <- upsert(con, "fait_production_mensuelle", faits_prod,
                     c("code_pays", "date_mois"))

    # --- Contrôles qualité : historisés par exécution ---
    if (nrow(donnees$anomalies) > 0) {
      dbWriteTable(con, "qc_anomalies", as.data.frame(donnees$anomalies), append = TRUE)
    }
    list(prix = r_prix, production = r_prod)
  })

  executer_sql(con, file.path(cfg$dir_sql, "02_vues.sql"))
  log_info("Chargement : ", res$prix$n_charges, " prix (", res$prix$n_nouveaux,
           " nouveaux), ", res$production$n_charges, " lignes de production")

  exporter_powerbi(con, cfg)
  res
}

# Export des tables du modèle en étoile (CSV + Parquet), lues par Power BI
exporter_powerbi <- function(con, cfg = CONFIG) {
  tables <- c("dim_pays", "dim_classe", "dim_date", "fait_prix_hebdo",
              "fait_production_mensuelle", "qc_anomalies")
  for (t in tables) {
    base <- file.path(cfg$dir_powerbi, t)
    dbExecute(con, sprintf("COPY %s TO '%s.csv' (HEADER, DELIMITER ',')", t, base))
    dbExecute(con, sprintf("COPY %s TO '%s.parquet' (FORMAT PARQUET)", t, base))
  }
  log_info("Export Power BI : ", length(tables), " tables écrites dans ", cfg$dir_powerbi)
}

# Trace l'exécution dans journal_chargement (succès comme échec)
journaliser <- function(cfg = CONFIG, run_id, debut, statut, res = NULL,
                        anomalies = NULL, message = NA_character_) {
  con <- connexion(cfg)
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
  executer_sql(con, file.path(cfg$dir_sql, "01_schema.sql"))
  ligne <- data.frame(
    run_id               = run_id,
    debut                = debut,
    fin                  = Sys.time(),
    statut               = statut,
    n_prix_charges       = res$prix$n_charges %||% NA_integer_,
    n_prix_nouveaux      = res$prix$n_nouveaux %||% NA_integer_,
    n_production_charges = res$production$n_charges %||% NA_integer_,
    n_anomalies          = if (is.null(anomalies)) NA_integer_ else nrow(anomalies),
    n_bloquantes         = if (is.null(anomalies)) NA_integer_ else
                             sum(anomalies$severite == "bloquant"),
    message              = message
  )
  dbWriteTable(con, "journal_chargement", ligne, append = TRUE)
}
