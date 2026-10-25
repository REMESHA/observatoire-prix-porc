# =============================================================================
# 01_extract.R — EXTRACT
# Interroge l'API Agri-food Data de la Commission européenne et conserve les
# réponses brutes (JSON) sans les modifier, un fichier par source et par année.
#
# Principe : les années anciennes déjà téléchargées ne sont pas redemandées
# (cache). Les années récentes sont ré-extraites à chaque lancement, car la
# Commission peut réviser les dernières semaines.
# =============================================================================

library(httr2)
library(jsonlite)

# Appel générique à l'API avec nouvelles tentatives en cas d'erreur réseau
appel_api <- function(endpoint, params, cfg = CONFIG) {
  req <- request(paste0(cfg$api_base, endpoint)) |>
    req_url_query(!!!params) |>
    req_timeout(cfg$timeout_s) |>
    req_user_agent("observatoire-prix-porc (projet portfolio, R/httr2)") |>
    req_retry(max_tries = cfg$max_essais, backoff = ~ 2^.x)

  resp <- req_perform(req)
  resp_body_string(resp)
}

# Une année = une requête (les réponses restent de taille raisonnable)
extraire_annee <- function(source, annee, cfg = CONFIG) {
  dossier <- file.path(cfg$dir_raw, source)
  dir.create(dossier, recursive = TRUE, showWarnings = FALSE)
  fichier <- file.path(dossier, sprintf("%s_%d.json", source, annee))

  annee_courante <- as.integer(format(Sys.Date(), "%Y"))
  recente <- annee > annee_courante - cfg$annees_a_rafraichir

  if (file.exists(fichier) && !recente) {
    log_info(source, " ", annee, " : déjà en cache, non ré-extrait")
    return(fichier)
  }

  params <- switch(
    source,
    # La fin de période déborde d'une semaine sur janvier suivant : l'API ne
    # renvoie une semaine que si elle est entièrement incluse dans l'intervalle,
    # et la semaine à cheval sur deux années (ex. 29/12/2025–04/01/2026)
    # serait sinon perdue. Le recouvrement est dédoublonné à l'étape Transform.
    prix = list(
      beginDate  = sprintf("01/01/%d", annee),
      endDate    = sprintf("07/01/%d", annee + 1L),
      pigClasses = paste(cfg$classes_prix, collapse = ",")
    ),
    production = list(years = annee),
    stop("Source inconnue : ", source)
  )
  if (!is.null(cfg$pays)) params$memberStateCodes <- paste(cfg$pays, collapse = ",")

  endpoint <- if (source == "prix") "/prices" else "/production"

  corps <- tryCatch(appel_api(endpoint, params, cfg), error = function(e) {
    log_error(source, " ", annee, " : échec de l'appel API — ", conditionMessage(e))
    NULL
  })
  if (is.null(corps)) return(if (file.exists(fichier)) fichier else NA_character_)

  n <- length(fromJSON(corps, simplifyVector = FALSE))
  if (n == 0) {
    log_warn(source, " ", annee, " : réponse vide (année sans données publiées ?)")
    return(NA_character_)
  }

  # Écriture atomique : fichier temporaire puis renommage
  tmp <- paste0(fichier, ".tmp")
  writeLines(corps, tmp, useBytes = TRUE)
  file.rename(tmp, fichier)
  log_info(source, " ", annee, " : ", n, " enregistrements extraits")
  fichier
}

extract <- function(cfg = CONFIG) {
  annees <- seq(cfg$annee_debut, cfg$annee_fin)
  fichiers <- list(
    prix       = vapply(annees, \(a) extraire_annee("prix", a, cfg), character(1)),
    production = vapply(annees, \(a) extraire_annee("production", a, cfg), character(1))
  )
  lapply(fichiers, \(f) f[!is.na(f)])
}
