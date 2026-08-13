# V12 — Centre de contrôle interactif

## Objectif

`menu.ps1` devient le point d'entrée humain principal du dépôt. Il ne remplace aucun orchestrateur existant : il route les choix vers `install.ps1`, `update.ps1` et les composants V7/V9/V10/V11 déjà testés.

L'objectif est de pouvoir gérer la workstation sans mémoriser les commandes PowerShell du dépôt.

## Lancement

Depuis PowerShell ou WezTerm :

```powershell
.\menu.ps1
```

Ou par double-clic :

```text
START_MENU.cmd
```

Le lanceur préfère PowerShell 7 (`pwsh.exe`) et utilise Windows PowerShell en fallback si PowerShell 7 n'est pas encore disponible.

## Menu principal

```text
1. Installation complète
2. Installation / réparation des logiciels
3. Mises à jour complètes
4. Sauvegarde
5. Restauration / rollback
6. Audit et diagnostic complet
7. Vérification de conformité
8. Composants spécifiques
9. Journaux et rapports
10. Aide
0. Quitter
```

## 1 — Installation complète

Route vers :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

L'orchestrateur V9 reste responsable de la découverte machine-first, du plan factuel, de l'idempotence et des validations.

## 2 — Logiciels uniquement

Route directement vers le composant WinGet existant :

```powershell
.\scripts\bootstrap\03_apps.ps1 -Mode Apply
```

Cette option ne relance pas volontairement toute l'installation Windows.

## 3 — Mises à jour

Route vers :

```powershell
.\update.ps1 -Mode Apply
```

La V11 conserve ses garde-fous : Windows Update, applications WinGet, WSL, Ubuntu/APT, extensions VS Code et versions DevOps épinglées, sans pilote/facultatif forcé ni redémarrage imposé.

## 4 — Sauvegarde

Sous-menu :

1. créer une sauvegarde V7 ;
2. vérifier une sauvegarde V7 existante.

Les chemins de destination restent demandés par le mécanisme V7 existant afin de ne pas dupliquer sa logique de sécurité.

## 5 — Restauration

Sous-menu :

1. générer le plan de restauration V7 ;
2. rollback des réglages gérés par le dépôt.

Le centre de contrôle ne prétend jamais effectuer une restauration complète destructive : la sauvegarde V7 expose volontairement un `RestorePlan`, tandis que `install.ps1 -Mode Rollback` restaure uniquement les états gérés et réellement enregistrés par le dépôt.

## 6 — Audit

```powershell
.\install.ps1 -Mode Audit
```

Observation et diagnostic sans appliquer le plan d'installation.

## 7 — Vérification

```powershell
.\install.ps1 -Mode Verify
```

Exige la conformité des composants vérifiés par l'orchestrateur.

## 8 — Composants spécifiques

Sous-menu :

- WSL2 + stack DevOps + validation ;
- OpenClaw / OpenRouter + validation ;
- qualification matérielle guidée.

Les opérations sont toujours déléguées à `install.ps1`, afin que le centre de contrôle ne recrée pas de seconde implémentation.

## 9 — Journaux et rapports

Permet d'ouvrir directement :

```text
logs\
reports\
```

## Élévation administrateur

Le menu affiche l'état Administrateur en haut de l'écran.

Lorsqu'une action nécessite les droits administrateur et que le menu n'est pas élevé, V12 relance uniquement le script cible via UAC puis attend son résultat. Les actions de lecture restent utilisables sans forcer l'élévation du menu complet.

## Confirmation

Les opérations de modification demandent confirmation avant lancement. Le rollback dispose d'un avertissement renforcé.

## Dry-run

Pour tester le routage sans exécuter de commande :

```powershell
.\menu.ps1 -Choice 1 -DryRun -NoPause -NoClear
.\menu.ps1 -Choice 3 -DryRun -NoPause -NoClear
.\menu.ps1 -Choice 4.1 -DryRun -NoPause -NoClear
.\menu.ps1 -Choice 5.1 -DryRun -NoPause -NoClear
.\menu.ps1 -Choice 8.1 -DryRun -NoPause -NoClear
```

Ce mode est utilisé par la CI V12 pour vérifier le routage sans modifier le runner.

## Contrat de non-régression

Le centre de contrôle doit rester une couche additive :

- aucune duplication de Windows Update ;
- aucune duplication de l'orchestrateur V9 ;
- aucune restauration destructive inventée ;
- aucune suppression des confirmations existantes ;
- aucune commande automatique vers `latest` pour les outils DevOps ;
- aucun bypass des mécanismes V7/V9/V10/V11.

La CI V12 parse le fichier, vérifie les routes et exécute les choix critiques en `DryRun`. Les workflows historiques restent également obligatoires avant fusion.
