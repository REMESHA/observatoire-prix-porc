-- =============================================================================
-- 01_schema.sql — Modèle de données (schéma en étoile)
--
--   dim_pays ─┐                       ┌─ dim_classe
--             ├── fait_prix_hebdo ────┤
--   dim_date ─┘
--   dim_pays ─┬── fait_production_mensuelle
--   dim_date ─┘
--
-- Tables techniques : qc_anomalies (contrôles qualité), journal_chargement.
-- Les clés primaires garantissent l'idempotence : relancer le pipeline
-- remplace les lignes existantes au lieu de créer des doublons.
-- =============================================================================

CREATE TABLE IF NOT EXISTS dim_pays (
    code_pays        VARCHAR PRIMARY KEY,   -- code UE à 2 lettres (EL = Grèce, EU = moyenne UE)
    nom_pays         VARCHAR NOT NULL,
    est_moyenne_ue   BOOLEAN NOT NULL,      -- vrai pour la moyenne UE (EU) uniquement
    est_agregat      BOOLEAN NOT NULL       -- vrai pour tout agrégat (EU, EU+UK) : à exclure des classements
);

CREATE TABLE IF NOT EXISTS dim_classe (
    classe           VARCHAR PRIMARY KEY,   -- E, S, R, Piglet
    libelle          VARCHAR NOT NULL,
    unite            VARCHAR NOT NULL,
    ordre_affichage  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS dim_date (
    date             DATE PRIMARY KEY,
    annee            INTEGER NOT NULL,
    trimestre        INTEGER NOT NULL,
    mois             INTEGER NOT NULL,
    nom_mois         VARCHAR NOT NULL,
    annee_mois       VARCHAR NOT NULL,      -- ex. 2026-10, pratique pour les axes
    annee_iso        INTEGER NOT NULL,
    semaine_iso      INTEGER NOT NULL,
    debut_semaine    DATE NOT NULL,         -- lundi de la semaine ISO
    debut_mois       DATE NOT NULL
);

CREATE TABLE IF NOT EXISTS fait_prix_hebdo (
    code_pays        VARCHAR NOT NULL,
    classe           VARCHAR NOT NULL,
    date_debut       DATE    NOT NULL,      -- lundi de la semaine de cotation
    date_fin         DATE,
    annee_iso        INTEGER NOT NULL,
    semaine_iso      INTEGER NOT NULL,
    prix             DOUBLE  NOT NULL,      -- €/kg carcasse ou €/tête (porcelets)
    unite            VARCHAR NOT NULL,
    variation_hebdo  DOUBLE,                -- variation relative vs semaine précédente
    prix_source      VARCHAR,               -- valeur telle que publiée (traçabilité)
    fichier_source   VARCHAR,
    run_id           VARCHAR NOT NULL,
    charge_le        TIMESTAMP NOT NULL,
    PRIMARY KEY (code_pays, classe, date_debut)
);

CREATE TABLE IF NOT EXISTS fait_production_mensuelle (
    code_pays                 VARCHAR NOT NULL,
    date_mois                 DATE    NOT NULL,
    annee                     INTEGER NOT NULL,
    mois                      INTEGER NOT NULL,
    production_kt             DOUBLE,   -- milliers de tonnes équivalent carcasse
    abattages_milliers_tetes  DOUBLE,
    poids_moyen_kg            DOUBLE,
    fichier_source            VARCHAR,
    run_id                    VARCHAR NOT NULL,
    charge_le                 TIMESTAMP NOT NULL,
    PRIMARY KEY (code_pays, date_mois)
);

CREATE TABLE IF NOT EXISTS qc_anomalies (
    run_id      VARCHAR NOT NULL,
    source      VARCHAR NOT NULL,
    code_pays   VARCHAR,
    serie       VARCHAR,
    date        DATE,
    valeur      DOUBLE,
    type        VARCHAR NOT NULL,
    severite    VARCHAR NOT NULL,
    detail      VARCHAR
);

CREATE TABLE IF NOT EXISTS journal_chargement (
    run_id               VARCHAR PRIMARY KEY,
    debut                TIMESTAMP NOT NULL,
    fin                  TIMESTAMP,
    statut               VARCHAR NOT NULL,   -- succes / echec
    n_prix_charges       INTEGER,
    n_prix_nouveaux      INTEGER,
    n_production_charges INTEGER,
    n_anomalies          INTEGER,
    n_bloquantes         INTEGER,
    message              VARCHAR
);
