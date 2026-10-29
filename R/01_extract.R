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

# Appel générique à l'API, avec nouvelles tentatives.
# req_retry() ne refait la requête qu'après une réponse d'erreur du serveur
# (429, 503...). Une coupure réseau (connexion fermée, délai dépassé) n'est pas
# retentée par défaut dans toutes les versions de httr2 : la boucle ci-dessous
# couvre ce cas, en attendant 2, 4 puis 8 secondes entre les essais.
appel_api <- function(endpoint, params, cfg = CONFIG) {
  req <- request(paste0(cfg$api_base, endpoint)) |>
    req_url_query(!!!params) |>
    req_timeout(cfg$timeout_s) |>
    req_user_agent("observatoire-prix-porc (projet portfolio, R/httr2)") |>
    req_retry(max_tries = 2, backoff = ~ 2^.x)   # erreurs 429/503 du serveur

  sous_windows <- .Platform$OS.type == "windows"

  for (essai in seq_len(cfg$max_essais)) {
    resultat <- tryCatch(resp_body_string(req_perform(req)), error = function(e) e)
    if (!inherits(resultat, "error")) return(resultat)

    # Repli sous Windows : certains postes (antivirus, proxy, réseau) coupent les
    # connexions de curl vers ce serveur, mais pas celles du système Windows.
    # On retente alors avec le client HTTP de Windows, via PowerShell.
    if (sous_windows) {
      repli <- tryCatch(telecharger_via_windows(req$url, cfg), error = function(e) e)
      if (!inherits(repli, "error")) {
        log_info("Téléchargement réussi via le client HTTP de Windows (repli)")
        return(repli)
      }
    }

    if (essai < cfg$max_essais) {
      log_warn("Essai ", essai, "/", cfg$max_essais, " échoué (",
               conditionMessage(resultat)[1], ") — nouvel essai dans ", 2^essai, " s")
      Sys.sleep(2^essai)
    }
  }
  stop(resultat)
}

# Téléchargement par Invoke-WebRequest (PowerShell), qui utilise la pile réseau
# de Windows, comme les navigateurs. Renvoie le corps de la réponse en texte.
telecharger_via_windows <- function(url, cfg = CONFIG) {
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)
  commande <- paste0(
    "$ProgressPreference = 'SilentlyContinue'; ",
    "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; ",
    "Invoke-WebRequest -Uri '", url, "' -OutFile '", normalizePath(tmp, mustWork = FALSE),
    "' -UseBasicParsing -TimeoutSec ", cfg$timeout_s
  )
  code <- system2("powershell", c("-NoProfile", "-NonInteractive", "-Command",
                                  shQuote(commande, type = "cmd")),
                  stdout = FALSE, stderr = FALSE)
  if (!identical(code, 0L) || !file.exists(tmp) || file.size(tmp) == 0) {
    stop("échec du téléchargement via PowerShell (code ", code, ")")
  }
  paste(readLines(tmp, encoding = "UTF-8", warn = FALSE), collapse = "\n")
}

# Liste des extractions échouées pendant l'exécution en cours
.echecs_extraction <- character()

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
  if (is.null(corps)) {
    .echecs_extraction <<- c(.echecs_extraction, paste(source, annee))
    if (file.exists(fichier)) {
      log_warn(source, " ", annee, " : la version déjà téléchargée est conservée (",
               format(file.mtime(fichier), "%d/%m/%Y"), ")")
      return(fichier)
    }
    return(NA_character_)
  }

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
  .echecs_extraction <<- character()
  annees <- seq(cfg$annee_debut, cfg$annee_fin)
  fichiers <- list(
    prix       = vapply(annees, \(a) extraire_annee("prix", a, cfg), character(1)),
    production = vapply(annees, \(a) extraire_annee("production", a, cfg), character(1))
  )
  resultat <- lapply(fichiers, \(f) f[!is.na(f)])
  attr(resultat, "echecs") <- .echecs_extraction
  resultat
}
