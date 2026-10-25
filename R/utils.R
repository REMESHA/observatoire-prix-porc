# =============================================================================
# utils.R — Fonctions communes : journalisation et petites aides
# =============================================================================

# Journal simple (console + fichier), sans dépendance externe
.log_file <- NULL

log_init <- function(dir_logs, run_id) {
  .log_file <<- file.path(dir_logs, paste0("pipeline_", run_id, ".log"))
  invisible(.log_file)
}

log_msg <- function(niveau = "INFO", ...) {
  ligne <- sprintf("[%s] %-5s %s",
                   format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                   niveau, paste0(...))
  message(ligne)
  if (!is.null(.log_file)) cat(ligne, "\n", file = .log_file, append = TRUE, sep = "")
}

log_info  <- function(...) log_msg("INFO", ...)
log_warn  <- function(...) log_msg("WARN", ...)
log_error <- function(...) log_msg("ERROR", ...)

# Valeur par défaut si NULL (natif seulement depuis R 4.4)
`%||%` <- function(x, y) if (is.null(x)) y else x

# "€1,185.50" -> 1185.5 ; renvoie NA si la valeur n'est pas interprétable
parse_prix <- function(x) {
  x <- gsub("[^0-9.,-]", "", x)   # retire le symbole € et les espaces
  x <- gsub(",", "", x)           # séparateur de milliers anglo-saxon
  suppressWarnings(as.numeric(x))
}

# "23/12/2024" -> Date
parse_date_fr <- function(x) as.Date(x, format = "%d/%m/%Y")

# "December" -> 12 (noms de mois anglais renvoyés par l'API)
mois_en_num <- function(x) {
  match(tolower(x), tolower(month.name))
}
