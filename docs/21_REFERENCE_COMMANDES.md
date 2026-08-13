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

Contrôle la conformité actuelle. Les options `-ValidateHardware`, `-ValidateWsl`, `-ValidateDevOps` et `-ValidateOpenClawAI` étendent la qualification.

## `-Mode Rollback`

```powershell
.\install.ps1 -Mode Rollback
```

Restaure uniquement les états initiaux que le dépôt sait réellement remettre en place.

---

# 3. Planification

## `-PlanOnly`

```powershell
.\install.ps1 -Mode Apply -PlanOnly
```

Construit le plan et s'arrête avant l'application.

Avec la stack DevOps :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps -PlanOnly
```

Périmètre complet :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

---

# 4. `-FullInstall` — comportement exact

Le code actuel active automatiquement :

```text
InstallDevOps
ValidateDevOps
ValidateWsl
ValidateHardware
InstallOpenClawAI
ValidateOpenClawAI
```

Donc :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

correspond à **la workstation complète avec OpenClaw/OpenRouter inclus**.

Pour une workstation core sans OpenClaw, préférer :

```powershell
.\install.ps1 `
  -Mode Apply `
  -InstallDevOps `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateHardware
```

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

# 9. OpenClaw/OpenRouter

Installer :

```powershell
.\install.ps1 -Mode Apply -InstallOpenClawAI
```

Valider :

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

Paramètres publics associés :

```text
-OpenClawRoot
-OpenClawControlPlanePath
-OpenClawRepositoryRef
```

Les valeurs par défaut placent l'intégration sous `D:\AI\OpenClaw`. Le ref du control-plane est normalement fourni par `config/openclaw/control-plane.json`.

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

# 13. Vocabulaire de sortie

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

# 14. Logs et rapports

Les sorties console sont complétées notamment par :

```text
logs\install.log
logs\<catégorie>\<script>.log
logs\runs\<RunId>\events.ndjson
logs\runs\<RunId>\summary.json
reports\orchestration\latest-run.json
reports\orchestration\machine-state.json
reports\updates\latest-run.json
```

---

## Commandes usuelles

Core sans OpenClaw :

```powershell
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Apply -InstallDevOps -ValidateWsl -ValidateDevOps -ValidateHardware -PlanOnly
.\install.ps1 -Mode Apply -InstallDevOps -ValidateWsl -ValidateDevOps -ValidateHardware
.\install.ps1 -Mode Verify -ValidateHardware -ValidateWsl -ValidateDevOps
```

Périmètre complet avec OpenClaw :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
.\install.ps1 -Mode Apply -FullInstall
```

Pour l'ordre exact des opérations, voir [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).