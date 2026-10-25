-- =============================================================================
-- 02_vues.sql — Vues analytiques
-- Elles répondent aux questions les plus fréquentes et servent de contrôle
-- croisé pour les mesures DAX du rapport Power BI.
-- =============================================================================

-- Prix de la classe E : France face à la moyenne de l'Union européenne
CREATE OR REPLACE VIEW v_prix_fr_vs_ue AS
SELECT
    fr.date_debut,
    fr.annee_iso,
    fr.semaine_iso,
    fr.prix                   AS prix_fr,
    ue.prix                   AS prix_ue,
    fr.prix - ue.prix         AS ecart_eur_kg,
    fr.prix / ue.prix - 1     AS ecart_relatif
FROM fait_prix_hebdo fr
JOIN fait_prix_hebdo ue
  ON ue.date_debut = fr.date_debut
 AND ue.classe     = fr.classe
 AND ue.code_pays  = 'EU'
WHERE fr.code_pays = 'FR'
  AND fr.classe    = 'E';

-- Variation sur un an, à semaine ISO identique (évite l'effet saisonnier)
CREATE OR REPLACE VIEW v_variation_annuelle AS
SELECT
    n.code_pays,
    n.classe,
    n.date_debut,
    n.annee_iso,
    n.semaine_iso,
    n.prix,
    n1.prix                 AS prix_annee_precedente,
    n.prix / n1.prix - 1    AS variation_annuelle
FROM fait_prix_hebdo n
LEFT JOIN fait_prix_hebdo n1
  ON n1.code_pays   = n.code_pays
 AND n1.classe      = n.classe
 AND n1.annee_iso   = n.annee_iso - 1
 AND n1.semaine_iso = n.semaine_iso;

-- Moyennes mensuelles par pays et par classe
CREATE OR REPLACE VIEW v_prix_mensuel AS
SELECT
    p.code_pays,
    p.classe,
    d.debut_mois,
    d.annee,
    d.mois,
    AVG(p.prix)   AS prix_moyen,
    MIN(p.prix)   AS prix_min,
    MAX(p.prix)   AS prix_max,
    COUNT(*)      AS n_semaines
FROM fait_prix_hebdo p
JOIN dim_date d ON d.date = p.date_debut
GROUP BY p.code_pays, p.classe, d.debut_mois, d.annee, d.mois;

-- Classement des pays sur la dernière semaine publiée (classe E)
CREATE OR REPLACE VIEW v_classement_derniere_semaine AS
WITH derniere AS (
    SELECT MAX(date_debut) AS date_debut
    FROM fait_prix_hebdo
    WHERE classe = 'E' AND code_pays = 'EU'
)
SELECT
    p.code_pays,
    dp.nom_pays,
    p.date_debut,
    p.prix,
    RANK() OVER (ORDER BY p.prix DESC) AS rang
FROM fait_prix_hebdo p
JOIN derniere   d  ON d.date_debut = p.date_debut
JOIN dim_pays   dp ON dp.code_pays = p.code_pays
WHERE p.classe = 'E'
  AND NOT dp.est_agregat;

-- Production annuelle et poids moyen par pays
CREATE OR REPLACE VIEW v_production_annuelle AS
SELECT
    code_pays,
    annee,
    SUM(production_kt)              AS production_kt,
    SUM(abattages_milliers_tetes)   AS abattages_milliers_tetes,
    SUM(production_kt) * 1000
      / NULLIF(SUM(abattages_milliers_tetes), 0) AS poids_moyen_kg,
    COUNT(*)                        AS n_mois
FROM fait_production_mensuelle
GROUP BY code_pays, annee;

-- Synthèse qualité par exécution
CREATE OR REPLACE VIEW v_qualite_par_execution AS
SELECT
    j.run_id,
    j.debut,
    j.statut,
    j.n_prix_charges,
    j.n_prix_nouveaux,
    j.n_anomalies,
    j.n_bloquantes
FROM journal_chargement j;
