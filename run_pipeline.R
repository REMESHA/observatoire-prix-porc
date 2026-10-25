#!/usr/bin/env Rscript
# =============================================================================
# run_pipeline.R — Orchestration du pipeline ETL
# Usage (depuis la racine du projet) :  Rscript run_pipeline.R
# =============================================================================

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

donnees <- NULL
statut <- tryCatch({
  fichiers <- extract(CONFIG)
  if (length(fichiers$prix) == 0) stop("Aucun fichier de prix disponible")

  donnees <- transform(fichiers, CONFIG, run_id)
  res     <- load(donnees, CONFIG, run_id)

  journaliser(CONFIG, run_id, debut, "succes", res, donnees$anomalies)
  "succes"
}, error = function(e) {
  log_error("Pipeline interrompu : ", conditionMessage(e))
  try(journaliser(CONFIG, run_id, debut, "echec",
                  anomalies = donnees$anomalies, message = conditionMessage(e)))
  "echec"
})

log_info(sprintf("=== Fin du pipeline : %s (%.0f s) ===", statut,
                 as.numeric(difftime(Sys.time(), debut, units = "secs"))))
quit(status = if (statut == "succes") 0 else 1)
