# Référence des commandes — interfaces publiques du projet

Ce document décrit les **points d'entrée publics réellement exposés par le code**. Il complète le Runbook [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).

Les scripts internes de `scripts/` ne sont pas tous destinés à être lancés directement. Les interfaces principales sont :

```text
START_MENU.cmd / menu.ps1 -> interface humaine
install.ps1               -> audit, convergence, validation, rollback, backup
update.ps1                -> maintenance multi-couches
```

## 1. `menu.ps1`

Lancement :

```powershell
.\menu.ps1
```

ou :

```text
START_MENU.cmd
```

Le menu route les intentions vers les orchestrateurs existants ; il ne remplace pas leur logique.

Mode de test de routage :

```powershell
.\menu.ps1 -Choice 6 -DryRun -NoPause -NoClear
```

Voir [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md).

---

# 2. `install.ps1`

Syntaxe :

```powershell
.\install.ps1 -Mode <Audit|Apply|Verify|Rollback> [options]
```

## `-Mode Audit`

```powershell
.\install.ps1 -Mode Audit
```

Observe l'état réel et produit les faits nécessaires au diagnostic. Il ne cherche pas à faire converger la machine.

## `-Mode Apply`

```powershell
.\install.ps1 -Mode Apply
```

Construit le plan à partir de `Verify`, applique les écarts du périmètre demandé puis re-vérifie.

## `-Mode Verify`

```powershell
.\install.ps1 -Mode Verify
```

Contrôle la conformité actuelle. Les options `-ValidateHardware`, `-ValidateWsl` et `-ValidateDevOps` étendent la qualification.

## `-Mode Rollback`

```powershell
.\install.ps1 -Mode Rollback
```

Restaure uniquement les états initiaux que le dépôt sait réellement remettre en place.

---

# 3. Planification

## Prérequis V25 des modes stricts

Avant le premier `PlanOnly`, `Apply` ou `Verify` strict :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Audit
.\scripts\bootstrap\00_storage_identity_v25.ps1 `
  -Mode Record `
  -ConfirmHealthyTopology
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Verify
```

`Record` est un enrôlement unique après contrôle humain. Si la baseline existe,
exécuter seulement `-Mode Verify`. Référence :
[`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md).

## `-PlanOnly`

```powershell
.\install.ps1 -Mode Apply -PlanOnly
```

Construit le plan et s'arrête avant l'application.

Avec la stack DevOps :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps -PlanOnly
```

Workstation complète :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

---

# 4. `-FullInstall` — comportement exact

Le code active automatiquement :

```text
InstallDevOps
ValidateDevOps
ValidateWsl
ValidateHardware
```

Donc :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

correspond à **la workstation Windows/WSL2/DevOps complète**.

Aucun projet externe n'est installé ou configuré par `-FullInstall`.

---

# 5. Paramètres WSL2

## `-WslProfile`

Valeurs :

```text
standard
lab-heavy
nat-fallback
```

Exemple :

```powershell
.\install.ps1 -Mode Apply -WslProfile lab-heavy
```

## `-Distribution`

Valeur par défaut : `Ubuntu`.

## `-WslInstallLocation`

Valeur par défaut :

```text
D:\WSL\Ubuntu-DevOps
```

## `-WslUser`

Permet de fournir explicitement l'utilisateur Linux lorsque nécessaire.

Ne jamais fournir un mot de passe dans une ligne de commande documentée ou journalisée.

---

# 6. Stack DevOps

Installer ou réparer :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

Valider :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl -ValidateDevOps
```

Les versions reproductibles sont définies dans `config/devops/tool-versions.env`.

---

# 7. Qualification matérielle

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

La qualification combine faits observables et preuves manuelles lorsque le système ne peut pas déduire une information de manière fiable.

Voir [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

---

# 8. Profils d'optimisation Windows

Paramètre :

```text
-OptimizationProfiles
```

Valeurs :

```text
standard
privacy
gaming
optional
```

Exemple :

```powershell
.\install.ps1 -Mode Apply -OptimizationProfiles standard,gaming
```

Le profil `standard` reste la base. Les profils supplémentaires sont explicites.

Voir [`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md).

## Point de restauration avant changements

Le code expose actuellement le switch technique :

```text
-SkipV4RestorePoint
```

Ce nom historique reste documenté parce qu'il fait encore partie de l'interface réelle de `install.ps1`. Il permet d'ignorer explicitement la création du point de restauration préalable aux changements planifiés.

Ce switch n'est pas recommandé dans le parcours normal.

---

# 9. Projets externes

OpenClaw/OpenRouter n'est pas une interface publique de `install.ps1`.

Les anciens paramètres suivants ne font plus partie du dépôt Windows :

```text
-InstallOpenClawAI
-ValidateOpenClawAI
-OpenClawRoot
-OpenClawControlPlanePath
-OpenClawRepositoryRef
```

L'installation et la configuration de la plateforme IA sont gérées par `mathiasseguincadiche/openclaw_openrouter`.

Voir [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

# 10. Sauvegarde

Actions :

```text
-BackupAction None
-BackupAction Create
-BackupAction Verify
-BackupAction RestorePlan
```

Exemples :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
.\install.ps1 -BackupAction RestorePlan -BackupTargetDrive E:
```

`E:` est un exemple ; utiliser la lettre réelle du support.

Paramètres associés :

```text
-BackupTargetDrive
-AllowNonUsbBackupTarget
-SkipBackupRestorePoint
```

Les deux switches de contournement sont des options avancées ; ils ne changent pas la politique recommandée du projet.

Voir [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

# 11. Automatisation

## `-NonInteractive`

Indique que l'exécution ne doit pas dépendre des questions interactives ordinaires.

## `-Yes`

Autorise la poursuite d'une exécution non interactive lorsque la confirmation des changements est requise.

## `-PlanOnly`

Prévisualise le plan sans appliquer les changements.

Ces options ne remplacent pas les preuves humaines impossibles à automatiser.

---

# 12. `update.ps1`

Syntaxe :

```powershell
.\update.ps1 -Mode <Audit|Apply|Verify> [options]
```

Modes :

```powershell
.\update.ps1 -Mode Audit
.\update.ps1 -Mode Apply
.\update.ps1 -Mode Verify
```

Le gestionnaire couvre Windows Update, WinGet, le runtime WSL, Ubuntu/APT, les outils DevOps épinglés et les extensions VS Code.

## Paramètres de périmètre

```text
-IncludeDrivers
-IncludeOptionalUpdates
-IncludeUnknownPackages
```

Ils sont opt-in.

## Paramètres WSL / Ubuntu

```text
-Distribution
-LinuxUser
```

`-Distribution` vaut `Ubuntu` par défaut. `-LinuxUser` permet de préciser le compte Linux pour les opérations qui en ont besoin.

## Plan de maintenance

```powershell
.\update.ps1 -Mode Apply -PlanOnly
```

## Automatisation et redémarrage

```text
-NonInteractive
-Yes
-NoRestartPrompt
```

Le gestionnaire peut détecter qu'un redémarrage est requis ; il ne doit pas le forcer silencieusement.

Voir [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

# 13. Preuves V26 et restauration isolée

Audit simulé :

```powershell
.\scripts\windows\90_workstation_fingerprint_v26.ps1 -Mode Audit
```

Audit ou vérification physique sur la workstation réelle :

```powershell
.\scripts\windows\90_workstation_fingerprint_v26.ps1 `
  -Mode Verify `
  -EvidenceLevel PHYSICAL `
  -ConfirmPhysicalEvidence
```

Le premier `Record` exige explicitement `-EvidenceLevel PHYSICAL`,
`-ConfirmPhysicalEvidence` et `-ConfirmHealthyState`. Un remplacement exige en
plus `-ReplaceBaseline` et `-ReplacementReason`; l'ancienne baseline et son
SHA-256 sont archivés.

Vérification d'une session Golden Backup :

```powershell
.\scripts\backup\63_restore_drill_v26.ps1 `
  -BackupSessionPath '<session>' `
  -Mode Verify
```

Le mode `Sandbox` ajoute `-ScratchRoot` et
`-ConfirmIsolatedRestoreDrill`. Il ne touche jamais à la distribution de
production.

Voir [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md).

---

# 14. Vocabulaire de sortie

| Statut | Sens |
| --- | --- |
| `DÉJÀ OK` | aucune correction nécessaire |
| `À FAIRE` | écart détecté |
| `EN COURS` | action en cours |
| `FAIT` | modification effectuée |
| `ACTION REQUISE` | décision ou preuve humaine nécessaire |
| `ATTENTE` | dépendance ou prochaine étape |
| `IGNORE` | hors périmètre demandé |
| `AVERTISSEMENT` | situation à surveiller |
| `ERREUR` | conformité non obtenue |

---

# 15. Logs et rapports

Les sorties console sont complétées notamment par :

```text
logs\install.log
logs\<catégorie>\<script>.log
logs\runs\<RunId>\events.ndjson
logs\runs\<RunId>\summary.json
reports\orchestration\latest-run.json
reports\orchestration\machine-state.json
reports\updates\latest-run.json
reports\workstation-v26\latest.json
```

---

## Commandes usuelles

```powershell
.\install.ps1 -Mode Audit
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Audit
# Premier enrôlement seulement, après contrôle humain :
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Record -ConfirmHealthyTopology
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Verify
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
.\install.ps1 -Mode Apply -FullInstall
.\install.ps1 -Mode Verify -ValidateHardware -ValidateWsl -ValidateDevOps
```

Pour l'ordre exact des opérations, voir [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).
