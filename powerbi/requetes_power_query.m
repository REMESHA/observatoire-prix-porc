// =============================================================================
// requetes_power_query.m — Requêtes Power Query (langage M)
//
// Deux façons de charger les données. Choisir UNE option.
//
// OPTION A (recommandée pour le portfolio) : lire les CSV publiés sur GitHub.
//   Le rapport se met à jour avec un simple « Actualiser », puisque GitHub
//   Actions actualise les CSV chaque semaine.
//
// OPTION B : lire les fichiers Parquet produits en local par le pipeline.
//
// Mode d'emploi : Accueil > Transformer les données > Nouvelle source >
// Requête vide > Éditeur avancé > coller le bloc > renommer la requête
// avec le nom indiqué en tête du bloc.
// =============================================================================


// =============================== OPTION A ====================================

// ---- Requête « fnChargerCSV » (fonction) ----
let
    fnChargerCSV = (nomTable as text) as table =>
    let
        Url    = "https://raw.githubusercontent.com/REMESHA/observatoire-prix-porc/main/data/powerbi/"
                 & nomTable & ".csv",
        Brut   = Csv.Document(Web.Contents(Url),
                    [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
        Entete = Table.PromoteHeaders(Brut, [PromoteAllScalars = true])
    in
        Entete
in
    fnChargerCSV

// Le paramètre "en-US" des conversions de type est indispensable : les CSV
// utilisent le point décimal et des dates ISO, alors qu'un Power BI réglé en
// français attend la virgule.

// ---- Requête « dim_pays » ----
let
    Source = fnChargerCSV("dim_pays"),
    Types  = Table.TransformColumnTypes(Source, {
        {"code_pays", type text}, {"nom_pays", type text},
        {"est_moyenne_ue", type logical}, {"est_agregat", type logical}
    }, "en-US")
in
    Types

// ---- Requête « dim_classe » ----
let
    Source = fnChargerCSV("dim_classe"),
    Types  = Table.TransformColumnTypes(Source, {
        {"classe", type text}, {"libelle", type text}, {"unite", type text},
        {"ordre_affichage", Int64.Type}
    }, "en-US")
in
    Types

// ---- Requête « dim_date » ----
let
    Source = fnChargerCSV("dim_date"),
    Types  = Table.TransformColumnTypes(Source, {
        {"date", type date}, {"annee", Int64.Type}, {"trimestre", Int64.Type},
        {"mois", Int64.Type}, {"nom_mois", type text}, {"annee_mois", type text},
        {"annee_iso", Int64.Type}, {"semaine_iso", Int64.Type},
        {"debut_semaine", type date}, {"debut_mois", type date}
    }, "en-US")
in
    Types

// ---- Requête « fait_prix_hebdo » ----
let
    Source = fnChargerCSV("fait_prix_hebdo"),
    Types  = Table.TransformColumnTypes(Source, {
        {"code_pays", type text}, {"classe", type text},
        {"date_debut", type date}, {"date_fin", type date},
        {"annee_iso", Int64.Type}, {"semaine_iso", Int64.Type},
        {"prix", type number}, {"unite", type text}, {"variation_hebdo", type number},
        {"prix_source", type text}, {"fichier_source", type text},
        {"run_id", type text}, {"charge_le", type datetime}
    }, "en-US")
in
    Types

// ---- Requête « fait_production_mensuelle » ----
let
    Source = fnChargerCSV("fait_production_mensuelle"),
    Types  = Table.TransformColumnTypes(Source, {
        {"code_pays", type text}, {"date_mois", type date},
        {"annee", Int64.Type}, {"mois", Int64.Type},
        {"production_kt", type number}, {"abattages_milliers_tetes", type number},
        {"poids_moyen_kg", type number}, {"fichier_source", type text},
        {"run_id", type text}, {"charge_le", type datetime}
    }, "en-US")
in
    Types

// ---- Requête « qc_anomalies » ----
let
    Source = fnChargerCSV("qc_anomalies"),
    Types  = Table.TransformColumnTypes(Source, {
        {"run_id", type text}, {"source", type text}, {"code_pays", type text},
        {"serie", type text}, {"date", type date}, {"valeur", type number},
        {"type", type text}, {"severite", type text}, {"detail", type text}
    }, "en-US")
in
    Types


// =============================== OPTION B ====================================
// Créer d'abord un paramètre « DossierDonnees » (Accueil > Gérer les paramètres)
// contenant le chemin complet du dossier data\powerbi du projet, par exemple :
//   C:\Users\darcy\observatoire-prix-porc\data\powerbi\
// Les fichiers Parquet conservent les types : aucune conversion n'est nécessaire.

// ---- Requête « fait_prix_hebdo » (même principe pour les autres tables) ----
let
    Source = Parquet.Document(File.Contents(DossierDonnees & "fait_prix_hebdo.parquet"))
in
    Source
