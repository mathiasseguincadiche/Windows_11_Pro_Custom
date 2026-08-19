# Centre de contrôle interactif

Le dépôt possède une interface interactive pour piloter la workstation sans devoir mémoriser toutes les commandes PowerShell.

Le menu est **une façade ergonomique** au-dessus des orchestrateurs existants. Il ne possède pas sa propre logique d'installation ou de maintenance.

## Démarrage

Depuis l'Explorateur Windows :

```text
START_MENU.cmd
```

Depuis PowerShell ou Windows Terminal :

```powershell
.\menu.ps1
```

## Ce que le menu permet de faire

Le centre de contrôle regroupe les intentions principales :

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

Les intitulés peuvent évoluer avec le dépôt, mais la responsabilité reste la même : **orienter l'utilisateur vers le bon moteur**.

La vérification de conformité globale active réellement les validations matériel,
WSL et DevOps. Le sous-menu des composants expose également l'empreinte
`SIMULATED`, les preuves `PHYSICAL`, ainsi que l'enregistrement ou le remplacement
justifié de la baseline. Les menus Sauvegarde et Restauration donnent accès au
`Verify` V26 et au drill WSL isolé avec confirmation explicite.

## Architecture

```text
Utilisateur
   ↓
START_MENU.cmd / menu.ps1
   │
   ├── installation / réparation ──► install.ps1
   ├── mises à jour ───────────────► update.ps1
   ├── sauvegarde / reprise ───────► mécanismes de backup
   ├── audit / vérification ───────► validateurs existants
   └── logs / rapports ────────────► logs\ et reports\
```

Aucune fonctionnalité métier importante ne doit exister uniquement dans le menu.

## Installation complète

Le choix d'installation complète correspond à l'orchestration globale de la workstation :

- vérification stricte de la baseline d'identité physique V25 de `C:` et `E:` ;
- inspection de l'état réel ;
- applications Windows ;
- réglages gérés ;
- WSL2 ;
- environnement DevOps ;
- workstation VS Code / Windows Terminal ;
- validations pertinentes.

Lors d'une première configuration, le menu bloque volontairement si la baseline
V25 n'a pas encore été enregistrée après contrôle humain. Effectuer d'abord
`Audit → V25 Record → V25 Verify` selon
[`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md),
puis relancer exactement **Installation complète**.

Il ne déclenche aucun projet externe. En particulier, OpenClaw/OpenRouter n'est ni installé ni configuré depuis ce menu.

Le guide pas à pas depuis un Windows vierge reste [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md).

## Installation / réparation des logiciels

Cette section sert à corriger un socle applicatif partiellement installé sans reconstruire toute la machine.

Le principe reste idempotent : un logiciel déjà conforme ne doit pas être réinstallé simplement parce que l'utilisateur a ouvert ce menu.

## Mises à jour

Le menu route vers `update.ps1` et sa politique de maintenance.

Documentation : [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

## Sauvegarde et restauration

Le menu donne accès aux opérations de sauvegarde et aux plans de restauration, mais ne transforme pas une action destructive en simple clic sans garde-fou.

Documentation : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

## Audit et diagnostic

L'audit sert à répondre à une question simple :

> Quel est l'état réel de la workstation maintenant ?

Les diagnostics doivent s'appuyer sur les faits machine, les logs et les validateurs, pas sur la supposition qu'une installation précédente a forcément réussi.

## Vérification de conformité

La vérification utilise les contrats actuels du dépôt :

- Windows ;
- stockage ;
- WSL2 ;
- DevOps ;
- Windows Terminal ;
- matériel lorsque demandé.

Les projets externes ne font pas partie du verdict de conformité de la workstation.

Guide : [`11_VALIDATION.md`](11_VALIDATION.md).

## Composants spécifiques

Cette partie permet d'agir sur une brique sans exécuter l'ensemble du parcours. Le contrat courant expose :

```text
1. WSL2 + stack DevOps + validation
2. Qualification matérielle guidée
```

Elle est utile pour le dépannage et la maintenance ciblée.

Windows Terminal reste intégré à la phase workstation normale et peut aussi être diagnostiqué directement avec `scripts/windows/31_windows_terminal.ps1`.

OpenClaw/OpenRouter n'est pas un composant du centre de contrôle `Windows_11_Pro_Custom` ; ce projet possède son propre dépôt et ses propres points d'entrée.

## Journaux et rapports

Le menu permet d'accéder rapidement à :

```text
logs\
reports\
```

Les journaux expliquent ce qui a été observé et exécuté. Les rapports stockent des validations ou mesures structurées.

## UAC et privilèges

Le menu ne doit pas être exécuté systématiquement avec des privilèges maximaux « au cas où ».

Il demande ou relaie l'élévation lorsque l'action ciblée l'exige réellement.

Cela limite la surface de risque et rend plus clair ce qui nécessite des droits administrateur.

## Mode de test

Le menu dispose d'un mode de routage non destructif utilisé par les tests :

```powershell
.\menu.ps1 -Choice 1 -DryRun -NoPause -NoClear
```

Ce mode sert à vérifier qu'un choix appelle le bon orchestrateur sans appliquer la modification sur un runner CI.

## Pour un utilisateur débutant

La règle recommandée est :

```text
Je veux comprendre le projet
        ↓
README.md / docs/README.md

Je veux installer depuis zéro
        ↓
01_INSTALLATION_WINDOWS.md

La machine est installée
        ↓
menu.ps1

Je veux comprendre ce que fait le menu
        ↓
14_ORCHESTRATION.md
```

Le centre de contrôle améliore l'ergonomie ; **il n'est pas l'identité du projet**. L'identité reste une workstation Windows 11 Pro reproductible, orientée DevOps/Ops, performante, sécurisée et récupérable.
