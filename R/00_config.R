# =============================================================================
# 00_config.R — Paramètres du pipeline
# Tous les réglages modifiables sont ici : aucun chemin ni paramètre « en dur »
# dans les autres scripts.
# =============================================================================

CONFIG <- list(
  # --- Source : API de la Commission européenne (portail Agri-food Data) ---
  api_base = "https://api.tech.ec.europa.eu/agrifood/api/pigmeat",

  # --- Périmètre ---
  annee_debut   = 2015L,                     # historique chargé au premier lancement
  annee_fin     = as.integer(format(Sys.Date(), "%Y")),
  classes_prix  = c("E", "S", "R", "Piglet"), # classes de carcasse + porcelets
  pays          = NULL,                       # NULL = tous les États membres + moyenne UE
  pays_focus    = "FR",                       # pays mis en avant dans les vues

  # Rafraîchissement : nombre d'années récentes ré-extraites à chaque lancement
  # (les dernières semaines peuvent être révisées par la Commission).
  annees_a_rafraichir = 2L,

  # --- Contrôles qualité ---
  seuil_variation_hebdo = 0.15, # |variation sur une semaine| > 15 % => alerte
  seuil_z_robuste       = 5,    # score z robuste (médiane / MAD) au-delà => alerte

  # --- Chemins ---
  dir_raw     = "data/raw",
  dir_qc      = "data/qc",
  dir_powerbi = "data/powerbi",
  db_path     = "data/db/observatoire_porc.duckdb",
  dir_logs    = "logs",
  dir_sql     = "sql",

  # --- Réseau ---
  timeout_s  = 120,
  max_essais = 4
)

# Crée les dossiers s'ils n'existent pas
invisible(lapply(
  c(CONFIG$dir_raw, CONFIG$dir_qc, CONFIG$dir_powerbi,
    dirname(CONFIG$db_path), CONFIG$dir_logs),
  dir.create, recursive = TRUE, showWarnings = FALSE
))
