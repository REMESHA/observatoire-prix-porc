#!/usr/bin/env Rscript
# =============================================================================
# run_pipeline.R — Orchestration du pipeline ETL
# Usage (depuis la racine du projet) :
#   - Terminal :        Rscript run_pipeline.R
#   - Console RStudio : source("run_pipeline.R")
# =============================================================================

# Sous Windows, le moteur TLS par défaut de curl (schannel) coupe parfois la
# connexion avec l'API de la Commission (« server closed abruptly, missing
# close_notify »). OpenSSL est plus tolérant. Ce réglage doit être fait AVANT
# le chargement du paquet curl ; le fichier .Renviron du projet le fait aussi
# au démarrage de R.
if (.Platform$OS.type == "windows" && Sys.getenv("CURL_SSL_BACKEND") == "") {
  Sys.setenv(CURL_SSL_BACKEND = "openssl")
}

suppressPackageStartupMessages({
  source("R/00_config.R")
  source("R/utils.R")
  source("R/01_extract.R")
  source("R/02_transform.R")
  source("R/03_load.R")
})

run_id <- format(Sys.time(), "%Y%m%d_%H%M%S")
debut  <- Sys.time()
log_init(CONFIG$dir_logs, run_id)
log_info("=== Début du pipeline (run ", run_id, ") ===")

if (.Platform$OS.type == "windows") {
  log_info("Moteur TLS de curl : ", curl::curl_version()$ssl_version)
}

donnees <- NULL
statut <- tryCatch({
  fichiers <- extract(CONFIG)
  if (length(fichiers$prix) == 0) stop("Aucun fichier de prix disponible")
  echecs <- attr(fichiers, "echecs")

  donnees <- transform(fichiers, CONFIG, run_id)
  res     <- load(donnees, CONFIG, run_id)

  # « partiel » : le chargement a réussi, mais une partie des données n'a pas
  # pu être actualisée (on a gardé la version précédente).
  if (length(echecs) > 0) {
    msg <- paste("Non actualisé :", paste(echecs, collapse = ", "))
    log_warn(msg)
    journaliser(CONFIG, run_id, debut, "partiel", res, donnees$anomalies, message = msg)
    "partiel"
  } else {
    journaliser(CONFIG, run_id, debut, "succes", res, donnees$anomalies)
    "succes"
  }
}, error = function(e) {
  log_error("Pipeline interrompu : ", conditionMessage(e))
  try(journaliser(CONFIG, run_id, debut, "echec",
                  anomalies = donnees$anomalies, message = conditionMessage(e)))
  "echec"
})

log_info(sprintf("=== Fin du pipeline : %s (%.0f s) ===", statut,
                 as.numeric(difftime(Sys.time(), debut, units = "secs"))))

# Code de sortie pour GitHub Actions (seulement hors session interactive,
# pour ne pas fermer RStudio quand on lance le script avec source()).
# Un succès partiel est signalé comme une erreur : la CI doit alerter.
if (!interactive()) quit(status = if (statut == "succes") 0 else 1)
