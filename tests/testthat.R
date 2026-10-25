# Lance les tests depuis la racine du projet : Rscript tests/testthat.R
library(testthat)
suppressPackageStartupMessages({
  source("R/00_config.R")
  source("R/utils.R")
  source("R/02_transform.R")
  if (requireNamespace("duckdb", quietly = TRUE)) source("R/03_load.R")
})
log_info <- log_warn <- log_error <- function(...) invisible(NULL)  # silence

test_dir("tests/testthat", reporter = "summary", stop_on_failure = TRUE)
