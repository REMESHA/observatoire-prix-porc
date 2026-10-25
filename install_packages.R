# Installe les paquets nécessaires (à lancer une fois)
paquets <- c("httr2", "jsonlite", "dplyr", "tidyr", "readr", "DBI", "duckdb",
             "forecast", "ggplot2", "knitr", "rmarkdown", "testthat")
manquants <- paquets[!vapply(paquets, requireNamespace, logical(1), quietly = TRUE)]
if (length(manquants)) install.packages(manquants)
message("Paquets prêts. Quarto (https://quarto.org) est nécessaire pour le rapport.")
