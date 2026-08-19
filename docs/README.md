# Documentation officielle — Windows 11 Pro Custom

Ce dossier contient la documentation technique officielle de `Windows_11_Pro_Custom` : architecture, réalisation, WSL2, stack DevOps, terminal, validation, maintenance et reprise.

> La documentation active décrit l'état actuel. L'historique appartient à [`CHANGELOG.md`](../CHANGELOG.md) et à Git.

## Choisir le bon parcours

| Objectif | Parcours recommandé |
| --- | --- |
| Découvrir le projet | [`../README.md`](../README.md) → [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) → [`18_GUIDE_MAITRE.md`](18_GUIDE_MAITRE.md) |
| Réaliser le projet de A à Z | [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) |
| Installer Windows depuis zéro | [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) |
| Comprendre WSL2 | [`06_WSL2.md`](06_WSL2.md) ; guide pédagogique : [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md) |
| Utiliser la stack DevOps et Windows Terminal | [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md) |
| Comprendre la frontière OpenClaw/OpenRouter | [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md) |
| Comprendre l'orchestration | [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) |
| Trouver une commande | [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) |
| Vérifier la conformité | [`11_VALIDATION.md`](11_VALIDATION.md) → [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md) |
| Comprendre les niveaux de preuve et détecter la dérive | [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md) |
| Diagnostiquer | [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) → [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md) |
| Identifier les sources de vérité | [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md) |
| Reconstruire après incident | [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) → [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) |

## Carte documentaire

### Architecture et construction

- [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) — Windows / WSL2 / Windows Terminal / VS Code et frontières ;
- [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) — base Windows 11 Pro ;
- [`03_STOCKAGE.md`](03_STOCKAGE.md) — `C:`, `E:`, VHDX WSL2 et ext4 ;
- [`18_GUIDE_MAITRE.md`](18_GUIDE_MAITRE.md) — vue consolidée ;
- [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) — parcours officiel.

### Linux, DevOps et terminal

- [`06_WSL2.md`](06_WSL2.md) — contrat WSL2 ;
- [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md) — stack DevOps, `PowerShell 7 - DevOps`, `Ubuntu - DevOps`, shell Bash/Starship et VS Code ;
- [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md) — guide pédagogique.

### Projet externe OpenClaw/OpenRouter

[`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md) ne documente aucune installation IA. Il fixe uniquement la frontière : **OpenClaw/OpenRouter est installé, configuré et validé dans `mathiasseguincadiche/openclaw_openrouter`, jamais par ce dépôt Windows.**

### Exploitation

- [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) — machine-first, plan, Apply, Verify et idempotence ;
- [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md) — maintenance ;
- [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md) — `START_MENU.cmd` / `menu.ps1` ;
- [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) — interfaces publiques ;
- [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) — diagnostic ;
- [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md) — hiérarchie des contrats.

### Validation et reprise

- [`11_VALIDATION.md`](11_VALIDATION.md) — preuves de conformité ;
- [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md) — qualification matérielle ;
- [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md) — checklist finale ;
- [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md) — identité physique C:/E: et reprise après disparition d'un volume ;
- [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md) — niveaux `STATIC`/`SIMULATED`/`PHYSICAL`, empreinte V26 et restauration WSL isolée ;
- [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) — sauvegarde ;
- [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) — reconstruction.

## Règles documentaires

- un document = une responsabilité principale ;
- le README présente la workstation ;
- `07_DEVOPS_STACK.md` possède l'expérience terminal DevOps ;
- `19_OPENCLAW_OPENROUTER_WINDOWS.md` documente uniquement la frontière avec le projet IA externe ;
- le Runbook `20` donne l'ordre d'exécution ;
- le Runbook `13` reste réservé à la reprise ;
- `26_PREUVES_DRIFT_ET_RESTAURATION.md` distingue preuve CI et preuve physique ;
- `CHANGELOG.md` et Git conservent l'historique.

## Point de départ

Commencer par l'audit non mutatif :

```powershell
.\install.ps1 -Mode Audit
```

Sur une première installation, `PlanOnly`, `Apply` et `Verify` stricts exigent
ensuite la baseline d'identité physique V25 :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Audit
.\scripts\bootstrap\00_storage_identity_v25.ps1 `
  -Mode Record `
  -ConfirmHealthyTopology
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Verify
```

`Record` n'est autorisé qu'après contrôle humain de `C:` et `E:`. Si la
baseline existe déjà, exécuter uniquement `-Mode Verify`.

Puis prévisualiser la workstation complète :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Après validation physique complète, capturer l'empreinte globale V26 :

```powershell
.\scripts\windows\90_workstation_fingerprint_v26.ps1 `
  -Mode Audit `
  -EvidenceLevel PHYSICAL `
  -ConfirmPhysicalEvidence
```

Ordre canonique : [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).
Sécurité stockage : [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md).
Preuves et dérive : [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md).
