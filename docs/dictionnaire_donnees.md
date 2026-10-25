# Dictionnaire des données

Source unique : API du portail **Agri-food Data** de la Commission européenne
(`https://api.tech.ec.europa.eu/agrifood/api/pigmeat`), points d'accès
`/prices` (cotations hebdomadaires) et `/production` (abattages mensuels).

## Tables de dimensions

### `dim_pays`

| Colonne | Type | Description |
|---|---|---|
| `code_pays` | texte (clé) | Code à 2 lettres utilisé par la Commission (`EL` = Grèce, `EU` = moyenne de l'UE) |
| `nom_pays` | texte | Nom anglais publié par l'API |
| `est_moyenne_ue` | booléen | Vrai pour la ligne « European Union » (`EU`) |
| `est_agregat` | booléen | Vrai pour tout agrégat (`EU`, et `EU+UK` publié avant le Brexit) : à exclure des classements de pays |

Le code `UK` (Royaume-Uni) n'est présent que jusqu'au 1er février 2020.

### `dim_classe`

| Colonne | Type | Description |
|---|---|---|
| `classe` | texte (clé) | `S`, `E`, `R` (classes de carcasse, grille EUROP) ou `Piglet` |
| `libelle` | texte | Libellé en français |
| `unite` | texte | `EUR/kg carcasse` ou `EUR/tete` |
| `ordre_affichage` | entier | Ordre de tri dans les visuels |

### `dim_date`

Calendrier quotidien continu, du premier jour de données au 31 décembre de
l'année en cours (nécessaire à l'intelligence temporelle de Power BI).

| Colonne | Type | Description |
|---|---|---|
| `date` | date (clé) | Jour |
| `annee`, `trimestre`, `mois` | entier | Calendrier civil |
| `nom_mois` | texte | Nom du mois en français |
| `annee_mois` | texte | Format `AAAA-MM` |
| `annee_iso`, `semaine_iso` | entier | Semaine ISO 8601 (la semaine 1 contient le premier jeudi de l'année) |
| `debut_semaine` | date | Lundi de la semaine ISO |
| `debut_mois` | date | Premier jour du mois |

## Tables de faits

### `fait_prix_hebdo` — grain : pays × classe × semaine

| Colonne | Type | Description |
|---|---|---|
| `code_pays`, `classe`, `date_debut` | clé primaire | `date_debut` = lundi de la semaine de cotation |
| `date_fin` | date | Dimanche de la semaine |
| `annee_iso`, `semaine_iso` | entier | Recalculés à partir de `date_debut` |
| `prix` | décimal | **€/kg de carcasse** pour S, E, R (prix publié en €/100 kg divisé par 100) ; **€/tête** pour les porcelets |
| `unite` | texte | Unité harmonisée |
| `variation_hebdo` | décimal | Variation relative par rapport à la semaine précédente de la même série |
| `prix_source` | texte | Valeur exacte publiée (ex. `€185.00`), pour la traçabilité |
| `fichier_source` | texte | Fichier JSON brut d'origine |
| `run_id`, `charge_le` | texte, horodatage | Exécution du pipeline ayant chargé la ligne |

### `fait_production_mensuelle` — grain : pays × mois

| Colonne | Type | Description |
|---|---|---|
| `code_pays`, `date_mois` | clé primaire | `date_mois` = premier jour du mois |
| `annee`, `mois` | entier | |
| `production_kt` | décimal | Production en **milliers de tonnes équivalent carcasse** |
| `abattages_milliers_tetes` | décimal | Nombre de porcs abattus, en milliers |
| `poids_moyen_kg` | décimal | Poids moyen de carcasse (kg) |

Les unités de la production ne sont pas indiquées par l'API : elles ont été
déduites et vérifiées par un contrôle de cohérence
(`production_kt ≈ abattages_milliers_tetes × poids_moyen_kg / 1000`).

## Tables techniques

### `qc_anomalies`

Une ligne par anomalie détectée, historisée par exécution (`run_id`).

| Type | Sévérité | Règle |
|---|---|---|
| `valeur_invalide` | bloquant | Prix illisible, nul ou négatif — ligne écartée |
| `unite_inconnue` | bloquant | Unité différente de `100 KG` ou `P` — ligne écartée |
| `date_invalide` | bloquant | Date illisible — ligne écartée |
| `doublon_conflictuel` | alerte | Deux valeurs différentes pour la même semaine — valeur la plus récente conservée |
| `variation_brutale` | alerte | Variation sur une semaine supérieure à 15 % |
| `valeur_atypique` | alerte | Score z robuste (médiane / MAD) supérieur à 5 dans la série |
| `semaines_manquantes` | alerte | Écart de plus de 7 jours entre deux cotations successives |
| `incoherence_interne` | alerte | Production et têtes × poids moyen divergent de plus de 3 % |

Les seuils sont réglables dans `R/00_config.R`.

### `journal_chargement`

Une ligne par exécution : début, fin, statut, nombre de lignes chargées et
nouvelles, nombre d'anomalies.
