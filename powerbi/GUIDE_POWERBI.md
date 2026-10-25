# Guide de construction du rapport Power BI

Ce guide décrit, étape par étape, la construction du tableau de bord à partir
des tables produites par le pipeline. Compter **2 à 3 jours** pour une première
prise en main de Power BI.

> Power BI Desktop est gratuit mais ne fonctionne que sous **Windows**
> (Microsoft Store ou centre de téléchargement Microsoft).

Fichiers utiles dans ce dossier :

| Fichier | Rôle |
|---|---|
| `requetes_power_query.m` | Requêtes de chargement des données (langage M) |
| `mesures.dax` | Toutes les mesures DAX du rapport |
| `theme_observatoire.json` | Thème de couleurs |

---

## Étape 1 — Charger les données (Power Query)

1. Ouvrir Power BI Desktop, puis **Accueil > Transformer les données**.
2. Créer les requêtes de `requetes_power_query.m` (option A : CSV sur GitHub) :
   **Nouvelle source > Requête vide > Éditeur avancé**, coller le bloc, puis
   renommer la requête (`fnChargerCSV`, `dim_pays`, `dim_classe`, `dim_date`,
   `fait_prix_hebdo`, `fait_production_mensuelle`, `qc_anomalies`).
3. Vérifier dans l'aperçu que les prix ont bien des décimales (1,85 et non 185)
   et que les dates sont reconnues.
4. **Fermer et appliquer.**

Point à retenir pour l'entretien : le paramètre `"en-US"` des conversions de
type évite le piège classique du point décimal dans un Power BI configuré en
français.

## Étape 2 — Construire le modèle (vue Modèle)

Créer les relations suivantes (toutes **un-à-plusieurs**, filtrage **unique**,
de la dimension vers le fait) :

| De (côté 1) | Vers (côté plusieurs) |
|---|---|
| `dim_date[date]` | `fait_prix_hebdo[date_debut]` |
| `dim_pays[code_pays]` | `fait_prix_hebdo[code_pays]` |
| `dim_classe[classe]` | `fait_prix_hebdo[classe]` |
| `dim_date[date]` | `fait_production_mensuelle[date_mois]` |
| `dim_pays[code_pays]` | `fait_production_mensuelle[code_pays]` |

Puis :

- **Marquer `dim_date` comme table de dates** (clic droit sur la table >
  Marquer comme table de dates > colonne `date`). C'est indispensable pour
  `SAMEPERIODLASTYEAR` et `DATESINPERIOD`.
- Trier `nom_mois` par `mois` (sélectionner la colonne > **Trier par colonne**).
  Même chose pour `dim_classe[libelle]` avec `ordre_affichage`.
- Masquer dans la vue rapport les colonnes techniques : `run_id`,
  `fichier_source`, `prix_source`, et les clés des tables de faits
  (`code_pays`, `classe`, `date_debut`, `date_mois`), pour forcer l'usage des
  dimensions.
- `qc_anomalies` reste isolée (table de suivi, sans relation).

Le résultat est un **schéma en étoile** : c'est la structure recommandée par
Microsoft pour les performances et la simplicité du DAX.

## Étape 3 — Créer les mesures (DAX)

1. **Accueil > Entrer des données**, nommer la table `_Mesures`, charger.
2. Sélectionner `_Mesures`, puis **Nouvelle mesure** pour chaque formule de
   `mesures.dax`.
3. Supprimer la colonne vide de `_Mesures` : la table passe en tête de liste
   avec une icône de calculatrice.
4. Formats : prix en nombre décimal à 2 chiffres ; variations et écarts en
   pourcentage à 1 chiffre.

Mesures à savoir expliquer en entretien :

- **`Prix moyen`** renvoie vide si l'on mélange des unités (€/kg et €/tête des
  porcelets) : on évite d'afficher une moyenne absurde.
- **`Prix N-1`** utilise `SAMEPERIODLASTYEAR` (intelligence temporelle).
- **`Moyenne mobile 4 semaines`** utilise `DATESINPERIOD` sur 28 jours.
- **`Prix UE`** modifie le contexte de filtre avec `CALCULATE`.

Contrôle croisé : comparer quelques valeurs avec les vues SQL
(`v_prix_fr_vs_ue`, `v_variation_annuelle`) de la base DuckDB.

## Étape 4 — Appliquer le thème

**Affichage > Thèmes > Parcourir les thèmes** > `theme_observatoire.json`.

## Étape 5 — Construire les pages

Format conseillé : 16:9, un titre en haut à gauche, les segments
(filtres) sur une bande à gauche ou en haut, toujours au même endroit.

### Page 1 — Vue d'ensemble

- **Segments** : `dim_classe[libelle]` (sélection unique, valeur par défaut
  « Classe E ») ; `dim_date[date]` en curseur de période.
- **4 cartes** : `Prix dernière semaine` (filtre visuel : pays = France),
  `Variation sur un an`, `Écart vs UE (%)`, `Dernière mise à jour`.
- **Graphique en courbes** : axe X `dim_date[date]`, valeur `Prix moyen`,
  légende `dim_pays[nom_pays]`, filtré sur France, Allemagne, Espagne et
  Union européenne. Titre dynamique : **Format > Titre > fx** > mesure
  `Titre graphique prix`.
- **Graphique en courbes** : `Prix moyen` et `Moyenne mobile 4 semaines`
  (France seule).

### Page 2 — Comparaison européenne

- **Barres horizontales** : `dim_pays[nom_pays]` × `Prix dernière semaine`,
  triées par valeur décroissante ; mettre la France en évidence avec une
  couleur conditionnelle.
- **Matrice** : lignes `dim_pays[nom_pays]`, colonnes `dim_date[annee]`,
  valeur `Prix moyen`, avec **mise en forme conditionnelle > Couleur
  d'arrière-plan** (carte de chaleur).
- **Nuage de points** (optionnel) : `Écart vs UE (%)` × `Variation sur un an`
  par pays.

### Page 3 — Production

- **Histogramme groupé et courbe** : axe `dim_date[annee_mois]`, colonnes
  `Production (kt)`, courbe `Poids moyen carcasse (kg)` sur l'axe secondaire.
- **Matrice** : pays × année, `Production (kt)` et
  `Variation production sur un an`.

### Page 4 — Qualité des données

C'est la page qui distingue le projet : elle montre la gouvernance des données.

- **Cartes** : `Anomalies`, `Anomalies bloquantes`, `Dernière mise à jour`.
- **Histogramme** : nombre d'anomalies par `qc_anomalies[type]`.
- **Table** : détail des anomalies (date, pays, série, type, détail), triée
  par date décroissante.

### Info-bulles et navigation (si le temps le permet)

- Une page d'info-bulle (taille « Info-bulle ») affichant prix, variation sur
  un an et écart UE au survol d'un pays.
- Des boutons de navigation entre pages (**Insérer > Boutons > Navigateur de
  pages**).

## Étape 6 — Publier sur GitHub

Le partage public (« Publier sur le web ») exige un compte professionnel
Microsoft. À la place :

1. Enregistrer le fichier sous `powerbi/observatoire_prix_porc.pbix`.
2. **Fichier > Exporter > Exporter au format PDF** :
   `powerbi/observatoire_prix_porc.pdf`.
3. Faire une capture de chaque page et les placer dans `docs/img/`
   (`page1_vue_ensemble.png`, etc.).
4. Décommenter la section « Aperçu du tableau de bord » du `README.md`.

## Checklist avant d'envoyer la candidature

- [ ] Les quatre pages sont lisibles sans explication.
- [ ] Aucun visuel n'affiche une moyenne mélangeant €/kg et €/tête.
- [ ] Les chiffres clés correspondent aux vues SQL (contrôle croisé fait).
- [ ] Le `.pbix`, le PDF et les captures sont sur GitHub.
- [ ] Je sais expliquer le modèle en étoile, `CALCULATE` et l'intelligence
      temporelle en deux minutes.
