# Mettre le projet en ligne sur GitHub

Durée : 15 minutes environ.

## 1. Créer le dépôt

Sur GitHub, créer un dépôt **public** nommé `observatoire-prix-porc`, **sans**
README ni licence (ils existent déjà dans le projet).

> Si vous choisissez un autre nom, remplacez `observatoire-prix-porc` dans
> `README.md` (lien GitHub Pages) et dans `powerbi/requetes_power_query.m`
> (adresse des CSV).

## 2. Pousser le code

Le dossier est déjà un dépôt Git avec un premier commit. Depuis le dossier
du projet :

```bash
git remote add origin https://github.com/REMESHA/observatoire-prix-porc.git
git branch -M main
git push -u origin main
```

## 3. Autoriser GitHub Actions

Dans le dépôt GitHub :

1. **Settings > Actions > General > Workflow permissions** : cocher
   **Read and write permissions**, puis **Save**. Le pipeline peut ainsi
   enregistrer les données actualisées.
2. **Settings > Pages > Build and deployment > Source** : choisir
   **GitHub Actions**.

## 4. Lancer le pipeline une première fois

**Actions > Pipeline hebdomadaire > Run workflow**. Après 3 à 5 minutes :

- les données actualisées sont commitées par `github-actions[bot]` ;
- le rapport est en ligne à l'adresse
  `https://remesha.github.io/observatoire-prix-porc/`.

Le pipeline tourne ensuite seul chaque mercredi matin.

## 5. Ajouter le tableau de bord Power BI

Suivre [`powerbi/GUIDE_POWERBI.md`](../powerbi/GUIDE_POWERBI.md), puis
ajouter le `.pbix`, le PDF et les captures d'écran :

```bash
git add powerbi/observatoire_prix_porc.pbix powerbi/observatoire_prix_porc.pdf docs/img/
git commit -m "Ajout du tableau de bord Power BI"
git pull --rebase    # récupère d'abord les commits automatiques du pipeline
git push
```

Penser à décommenter la section « Aperçu du tableau de bord » du README.
