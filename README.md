# Windows 11 Pro Custom — workstation DevOps/Ops reproductible

[![Qualité](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/quality.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/quality.yml)
[![Runtime WSL](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/wsl-runtime-contract.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/wsl-runtime-contract.yml)
[![Documentation](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/documentation.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/documentation.yml)

`Windows_11_Pro_Custom` définit, automatise, vérifie et documente **une workstation Windows 11 Pro de référence pour DevOps/Ops**.

Le dépôt applique une approche **workstation-as-code** : l'état réel de la machine est observé avant modification, comparé aux contrats versionnés, corrigé uniquement lorsque nécessaire, puis re-vérifié. L'objectif n'est pas d'empiler des scripts d'installation, mais de conserver une machine reproductible, explicable, maintenable et récupérable.

> **Objectif :** pouvoir partir d'un Windows propre ou d'une machine déjà utilisée, retrouver la même architecture, comprendre ce qui est déjà conforme, appliquer uniquement ce qui manque, valider le résultat et conserver une sauvegarde de référence exploitable.

## Architecture de référence

```text
                         Windows 11 Pro
                              │
        ┌─────────────────────┼─────────────────────────┐
        │                     │                         │
        ▼                     ▼                         ▼
 desktop / sécurité      VS Code Windows        Windows Terminal
 pilotes / gaming               │                 ┌──────┴──────┐
 PowerShell / WinGet            │                 │             │
 Windows Update                 │                 ▼             ▼
                               │          PowerShell 7       Ubuntu WSL2
                               │            DevOps              │
                               └── WSL ─────────────────────────┤
                                                               ▼
                                                         Linux DevOps
                                                         Docker / K8s
                                                         Terraform
                                                         Ansible / AWS
```

La séparation fonctionnelle est volontaire :

```text
Windows          = hôte, desktop, sécurité, pilotes et administration
Ubuntu           = backend Linux DevOps et workspaces Linux
Windows Terminal = point d'entrée terminal vers PowerShell 7 et Ubuntu DevOps
VS Code          = interface Windows reliée aux projets WSL2
```

### Windows Terminal comme routeur de contextes

Windows Terminal expose deux profils gérés :

```text
PowerShell 7 - DevOps -> profil par défaut, administration Windows
Ubuntu - DevOps       -> Bash et outils Linux dans WSL2
```

Raccourcis gérés :

```text
Ctrl+Shift+1 -> PowerShell 7 - DevOps
Ctrl+Shift+2 -> Ubuntu - DevOps
Ctrl+Shift+O -> PowerShell + Ubuntu en panneaux
```

Le profil Ubuntu ne redéfinit pas Bash : il ouvre la distribution `Ubuntu`, dont le shell DevOps et Starship restent gérés par le contrat WSL versionné. Cette règle évite d'utiliser les projets Linux depuis un filesystem Windows comme racine quotidienne et maintient une frontière claire entre administration Windows et charges DevOps Linux.

Référence : [`docs/07_DEVOPS_STACK.md`](docs/07_DEVOPS_STACK.md).

## Contrats principaux

### Stockage

```text
C: NTFS -> Windows 11 Pro et composants système
E: NTFS -> données, WSL2, ISO et exports
```

Ubuntu utilise ext4 **dans son VHDX WSL2** stocké sous :

```text
E:\WSL\Ubuntu-DevOps
```

Les projets Linux actifs restent sous :

```text
~/projects
~/labs
~/repositories
```

et non sous `/mnt/c` ou `/mnt/e` comme racines principales.

### WSL2

```text
Distribution : Ubuntu 26.04
Nom          : Ubuntu
Emplacement  : E:\WSL\Ubuntu-DevOps
RAM          : 20 Go
CPU          : 8 threads
Swap         : 8 Go
Réseau       : mirrored
```

### DevOps

Ubuntu fournit la chaîne Linux de référence : Docker Engine, Compose/Buildx, Kubernetes CLI, Helm, Minikube, kind, Terraform, Ansible, AWS CLI, GitHub CLI et les outils qualité pilotés par les contrats du dépôt.

### OpenClaw/OpenRouter : hors périmètre

`Windows_11_Pro_Custom` **n'installe pas, ne configure pas, ne met pas à jour et ne valide pas OpenClaw/OpenRouter**.

La plateforme IA est un projet autonome, maintenu dans :

```text
mathiasseguincadiche/openclaw_openrouter
```

Ce dépôt spécialisé possède intégralement l'installation OpenClaw, la configuration OpenRouter, `clawops`, Gateway, modèles, agents, politiques et validations de la plateforme IA.

Le dépôt Windows se limite à construire et maintenir la workstation. Il ne clone pas le dépôt IA, ne référence pas son runtime lock et ne déclenche pas son installateur.

## Modèle d'orchestration

Le projet est machine-first :

```text
état réel
   ↓
Audit / Verify
   ↓
plan factuel
   ↓
Apply uniquement sur les écarts
   ↓
re-Verify
   ↓
preuve d'idempotence
   ↓
logs / rapports / sauvegarde
```

Les points d'entrée normaux sont :

```text
START_MENU.cmd / menu.ps1  -> interface humaine
install.ps1                -> audit, convergence, validation, rollback et backup
update.ps1                 -> maintenance structurée
```

Un composant déjà conforme doit rester `DÉJÀ OK`. Un ancien commit, un ancien rapport ou le simple fait qu'un script ait déjà tourné ne constitue pas une preuve de conformité actuelle.

## Installation de la workstation

Le parcours complet construit et qualifie Windows + WSL2 + DevOps :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

`-FullInstall` active :

```text
InstallDevOps
ValidateDevOps
ValidateWsl
ValidateHardware
```

Il ne déclenche aucun projet externe.

## Parcours recommandé

### 1. Observer

```powershell
.\install.ps1 -Mode Audit
```

### 2. Enrôler et vérifier l'identité physique V25

Cette étape est obligatoire une seule fois sur une topologie saine, avant tout
`PlanOnly`, `Apply` ou `Verify` strict :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Audit
.\scripts\bootstrap\00_storage_identity_v25.ps1 `
  -Mode Record `
  -ConfirmHealthyTopology
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Verify
```

Avant `Record`, vérifier humainement que `C:` est le volume Windows attendu et
que `E:` est le second Crucial T705 NTFS destiné aux données et à WSL. Une
baseline existante se vérifie simplement avec `-Mode Verify` et ne doit jamais
être remplacée pour masquer une alerte inexpliquée.

Référence : [`docs/25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](docs/25_IDENTITE_STOCKAGE_ET_RECUPERATION.md).

### 3. Prévisualiser

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

### 4. Faire converger

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

### 5. Prouver la conformité

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

### 6. Prouver l'idempotence

Recalculer ensuite le même plan :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Une workstation stabilisée doit tendre vers `DÉJÀ OK` et ne pas reproposer arbitrairement les mêmes mutations.

Le parcours complet est décrit dans [`docs/20_RUNBOOK_OPERATIONNEL.md`](docs/20_RUNBOOK_OPERATIONNEL.md).

## Quand le projet est-il terminé ?

Le résultat attendu combine :

```text
Windows qualifié
+
matériel qualifié
+
WSL2 conforme
+
stack DevOps conforme
+
Windows Terminal conforme
+
idempotence démontrée
+
preuves exploitables
+
sauvegarde vérifiée
```

La checklist officielle est [`docs/24_CRITERES_ACCEPTATION.md`](docs/24_CRITERES_ACCEPTATION.md).

## Sécurité et stabilité

Le projet privilégie la convergence contrôlée plutôt que les transformations globales :

- Windows Update, Defender, firewall et mécanismes essentiels restent des composants de la workstation ;
- les versions reproductibles viennent des contrats du dépôt, pas d'un `latest` pris arbitrairement ;
- les preuves matérielles non observables automatiquement restent explicites ;
- les changements sensibles ou destructifs ne sont pas assimilés à de la maintenance normale ;
- l'identité physique de `C:` et `E:` est enrôlée explicitement puis vérifiée avant toute convergence orchestrée par `install.ps1` et avant toute mutation WSL gérée par le dépôt ;
- la reconstruction après incident reste séparée du parcours quotidien.

## Documentation officielle

Le README présente le projet. Les procédures, contrats et diagnostics vivent dans `docs/`.

| Besoin | Référence |
| --- | --- |
| Architecture et frontières | [`docs/00_ARCHITECTURE.md`](docs/00_ARCHITECTURE.md) |
| Installation Windows | [`docs/01_INSTALLATION_WINDOWS.md`](docs/01_INSTALLATION_WINDOWS.md) |
| WSL2 | [`docs/06_WSL2.md`](docs/06_WSL2.md) |
| Stack DevOps et expérience terminal | [`docs/07_DEVOPS_STACK.md`](docs/07_DEVOPS_STACK.md) |
| Backup / restore | [`docs/10_BACKUP_RESTORE.md`](docs/10_BACKUP_RESTORE.md) |
| Validation | [`docs/11_VALIDATION.md`](docs/11_VALIDATION.md) |
| Orchestration | [`docs/14_ORCHESTRATION.md`](docs/14_ORCHESTRATION.md) |
| Guide WSL2 pédagogique | [`docs/16_WSL2_GUIDE_COMPLET.md`](docs/16_WSL2_GUIDE_COMPLET.md) |
| Centre de contrôle | [`docs/17_CONTROL_CENTER.md`](docs/17_CONTROL_CENTER.md) |
| Vue consolidée | [`docs/18_GUIDE_MAITRE.md`](docs/18_GUIDE_MAITRE.md) |
| Frontière avec OpenClaw/OpenRouter | [`docs/19_OPENCLAW_OPENROUTER_WINDOWS.md`](docs/19_OPENCLAW_OPENROUTER_WINDOWS.md) |
| Runbook opérationnel | [`docs/20_RUNBOOK_OPERATIONNEL.md`](docs/20_RUNBOOK_OPERATIONNEL.md) |
| Référence des commandes | [`docs/21_REFERENCE_COMMANDES.md`](docs/21_REFERENCE_COMMANDES.md) |
| Troubleshooting | [`docs/22_TROUBLESHOOTING.md`](docs/22_TROUBLESHOOTING.md) |
| Identité des SSD/partitions et disparition d'un volume | [`docs/25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](docs/25_IDENTITE_STOCKAGE_ET_RECUPERATION.md) |
| Sources de vérité | [`docs/23_SOURCES_DE_VERITE.md`](docs/23_SOURCES_DE_VERITE.md) |
| Critères d'acceptation | [`docs/24_CRITERES_ACCEPTATION.md`](docs/24_CRITERES_ACCEPTATION.md) |
| Reconstruction après incident | [`docs/13_RUNBOOK_REINSTALLATION.md`](docs/13_RUNBOOK_REINSTALLATION.md) |

Portail documentaire : [`docs/README.md`](docs/README.md).

La documentation active décrit **l'état actuel**. `CHANGELOG.md` et Git conservent l'historique.

## Organisation du dépôt

```text
Windows_11_Pro_Custom/
├── README.md
├── START_MENU.cmd
├── menu.ps1
├── install.ps1
├── update.ps1
├── config/        # contrats versionnés de la workstation
├── manifests/     # catalogues déclaratifs
├── scripts/       # implémentation workstation
├── docs/          # documentation officielle
├── logs/          # preuves d'exécution
├── reports/       # rapports structurés
└── .github/workflows/
```

En cas de divergence entre texte, scripts et état réel, suivre [`docs/23_SOURCES_DE_VERITE.md`](docs/23_SOURCES_DE_VERITE.md).
