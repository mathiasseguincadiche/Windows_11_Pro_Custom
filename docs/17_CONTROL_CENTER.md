# Centre de contrôle interactif

Le dépôt possède une interface interactive pour piloter la workstation sans mémoriser toutes les commandes PowerShell.

Le menu est **une façade ergonomique** au-dessus des orchestrateurs existants. Il ne possède pas sa propre logique métier.

## Démarrage

```text
START_MENU.cmd
```

ou :

```powershell
.\menu.ps1
```

## Fonctions exposées

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

## Architecture

```text
Utilisateur
   ↓
START_MENU.cmd / menu.ps1
   ├── installation / réparation -> install.ps1
   ├── mises à jour              -> update.ps1
   ├── sauvegarde / reprise      -> mécanismes de backup
   ├── audit / vérification      -> validateurs workstation
   └── logs / rapports           -> logs\ et reports\
```

Aucune fonctionnalité importante ne doit exister uniquement dans le menu.

## Installation complète

Le choix d'installation complète converge la workstation : applications Windows, réglages gérés, WSL2, stack DevOps, VS Code / WezTerm et qualifications demandées.

Il **ne déclenche pas OpenClaw/OpenRouter**. Ce projet externe possède son propre installateur et sa propre configuration.

## Composants spécifiques

Le sous-menu expose actuellement :

```text
1. WSL2 + stack DevOps + validation
2. Qualification matérielle guidée
```

OpenClaw/OpenRouter n'est pas un composant de ce centre de contrôle.

## Vérification de conformité

La vérification couvre les contrats du dépôt : Windows, stockage, WSL2, DevOps, terminal et matériel lorsque demandé.

Guide : [`11_VALIDATION.md`](11_VALIDATION.md).

## UAC et privilèges

Le menu relaie l'élévation uniquement lorsque l'action ciblée l'exige réellement.

## Mode de test

```powershell
.\menu.ps1 -Choice 1 -DryRun -NoPause -NoClear
```

Ce mode vérifie le routage sans appliquer de modification sur un runner CI.

## Pour un utilisateur débutant

```text
Comprendre -> README.md / docs/README.md
Installer depuis zéro -> 01_INSTALLATION_WINDOWS.md
Piloter la machine -> menu.ps1
Comprendre l'orchestration -> 14_ORCHESTRATION.md
```

Le centre de contrôle reste celui de la **workstation Windows 11 Pro DevOps/Ops**, et non celui des projets externes installés éventuellement sur la même machine.
