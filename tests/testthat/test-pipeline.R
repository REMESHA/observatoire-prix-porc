# Tests du pipeline — lancer depuis la racine : Rscript tests/testthat.R

racine <- normalizePath(file.path(testthat::test_path(), "..", ".."))
fixture <- function(f) file.path(racine, "tests", "fixtures", f)

cfg_test <- function() {
  dossier <- tempfile("pipeline_test_")
  dir.create(dossier)
  cfg <- CONFIG
  cfg$dir_qc      <- file.path(dossier, "qc")
  cfg$dir_powerbi <- file.path(dossier, "powerbi")
  cfg$db_path     <- file.path(dossier, "test.duckdb")
  cfg$dir_sql     <- file.path(racine, "sql")
  invisible(lapply(c(cfg$dir_qc, cfg$dir_powerbi), dir.create))
  cfg
}

test_that("parse_prix lit les formats publiés par l'API", {
  expect_equal(parse_prix("€185.00"), 185)
  expect_equal(parse_prix("€1,045.50"), 1045.5)
  expect_true(is.na(parse_prix("n.d.")))
})

test_that("dates et mois sont correctement interprétés", {
  expect_equal(parse_date_fr("23/12/2024"), as.Date("2024-12-23"))
  expect_equal(mois_en_num(c("January", "december")), c(1L, 12L))
})

test_that("la transformation harmonise les unités et signale les anomalies", {
  cfg <- cfg_test()
  res <- transform(list(prix = fixture("prix_test.json"),
                        production = fixture("production_test.json")),
                   cfg, run_id = "test")

  p <- res$prix
  # €/100 kg -> €/kg ; porcelet en €/tête
  expect_equal(p$prix[p$classe == "E" & p$code_pays == "FR" &
                        p$date_debut == as.Date("2025-01-06")], 1.80)
  expect_equal(p$prix[p$classe == "Piglet"], 45.5)
  # doublon supprimé
  expect_equal(sum(p$code_pays == "FR" & p$classe == "E" &
                     p$date_debut == as.Date("2025-01-13")), 1)

  types <- res$anomalies$type
  expect_true(all(c("valeur_invalide", "unite_inconnue", "doublon_conflictuel", "variation_brutale", "semaines_manquantes",
                    "incoherence_interne") %in% types))
  # les lignes bloquantes sont écartées
  expect_false(any(p$unite_source == "TONNE"))
})

test_that("le chargement est idempotent", {
  skip_if_not_installed("duckdb")
  cfg <- cfg_test()
  donnees <- transform(list(prix = fixture("prix_test.json"),
                            production = fixture("production_test.json")),
                       cfg, run_id = "test")
  r1 <- load(donnees, cfg, run_id = "run1")
  r2 <- load(donnees, cfg, run_id = "run2")

  expect_gt(r1$prix$n_nouveaux, 0)
  expect_equal(r2$prix$n_nouveaux, 0)

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = cfg$db_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  n <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM fait_prix_hebdo")$n
  expect_equal(n, nrow(donnees$prix))
  expect_true(file.exists(file.path(cfg$dir_powerbi, "fait_prix_hebdo.parquet")))
})

test_that("les doublons identiques sont supprimés sans alerte", {
  cfg <- cfg_test()
  res <- transform(list(prix = fixture("prix_test.json"),
                        production = fixture("production_test.json")),
                   cfg, run_id = "test")
  eu <- res$prix[res$prix$code_pays == "EU", ]
  expect_equal(nrow(eu), 1)
  expect_false(any(res$anomalies$code_pays == "EU" &
                     res$anomalies$type == "doublon_conflictuel"))
})
