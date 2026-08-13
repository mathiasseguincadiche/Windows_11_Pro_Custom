# Windows 11 Pro Custom — workstation DevOps/Ops reproductible

[![Qualité](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/quality.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/quality.yml)
[![Runtime WSL](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/wsl-runtime-contract.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/wsl-runtime-contract.yml)
[![Documentation](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/documentation.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/documentation.yml)

`Windows_11_Pro_Custom` définit, automatise, vérifie et documente **une workstation Windows 11 Pro de référence pour DevOps/Ops**.

Ce dépôt est une **workstation-as-code** : l'état attendu est versionné, l'état réel est observé avant modification, seuls les écarts utiles sont corrigés, puis le résultat est re-vérifié et documenté.

> **Objectif :** pouvoir partir d'un Windows propre ou d'une machine déjà utilisée, retrouver la même architecture, comprendre ce qui est conforme, appliquer ce qui manque, valider la workstation et conserver une sauvegarde de référence exploitable.

## Le projet en une minute

```text
Windows 11 Pro
├── desktop / gaming / pilotes / sécurité
├── PowerShell 7 / VS Code / WezTerm
│   └── profils terminal
│       ├── Ubuntu DevOps (WSL2)        <- défaut
│       ├── PowerShell 7                <- administration Windows
│       └── OpenClaw / clawops          <- CLI IA Windows-native
├── Windows Update / WinGet / sauvegarde
└── WSL2
    └── Ubuntu 26.04
        ├── Bash / Git
        ├── Docker / Kubernetes
        ├── Terraform / Ansible
        ├── AWS / GitHub CLI
        └── outils qualité

D:\AI\OpenClaw
├── OpenClaw Windows-native
├── clawops
└── état / workspace / control-plane
```

La règle structurante est :

```text
Windows gère l'expérience Windows et le runtime OpenClaw.
Linux gère les workloads Linux DevOps.
```

Les projets Linux actifs vivent sur ext4 dans `~/projects`, `~/labs` ou `~/repositories`.

## Contrats principaux

### Stockage

```text
C: NTFS -> Windows 11 Pro
D: NTFS -> données + WSL2 + OpenClaw
```

Ubuntu utilise ext4 **dans son VHDX WSL2** stocké sous `D:\WSL\Ubuntu-DevOps`.

### WSL2

```text
Distribution : Ubuntu 26.04
Nom          : Ubuntu
Emplacement  : D:\WSL\Ubuntu-DevOps
RAM          : 20 Go
CPU          : 8 threads
Swap         : 8 Go
Réseau       : mirrored
```

### DevOps

Ubuntu fournit Docker, Kubernetes, Terraform, Ansible, AWS CLI, GitHub CLI et les outils qualité définis par les contrats du dépôt.

### Terminal / WezTerm

WezTerm est le point d'accès quotidien aux trois contextes sans les mélanger :

```text
Ubuntu DevOps (WSL2)          -> Bash et outils Linux
PowerShell 7                  -> administration Windows
OpenClaw / clawops (Windows)  -> CLI IA native Windows
```

Le profil OpenClaw **ne lance automatiquement ni agent, ni Gateway, ni onboarding, ni action sensible**. Il ouvre une session PowerShell 7, recharge dans cette session les variables utilisateur OpenClaw, ajoute uniquement à son `PATH` les répertoires CLI gérés sous `D:\AI\OpenClaw`, puis vérifie si `openclaw` et `clawops` sont disponibles.

Ces ajustements restent limités à la session terminal : WezTerm ne remplace ni l'installation ni la validation OpenClaw et ne modifie pas les contrats persistants du control-plane.

Documentation : [`docs/07_DEVOPS_STACK.md`](docs/07_DEVOPS_STACK.md) et [`docs/19_OPENCLAW_OPENROUTER_WINDOWS.md`](docs/19_OPENCLAW_OPENROUTER_WINDOWS.md).

## Fonctionnement de l'orchestration

```text
état réel
   ↓
Verify
   ↓
plan factuel
   ↓
Apply sur les écarts
   ↓
re-Verify
   ↓
logs / rapports / verdict
```

Les points d'entrée sont :

```text
START_MENU.cmd / menu.ps1  -> interface humaine
install.ps1                -> audit / convergence / validation / rollback / backup
update.ps1                 -> maintenance
```

Un composant déjà conforme doit rester `DÉJÀ OK`. Le fait qu'un script ait été exécuté auparavant n'est pas une preuve de conformité.

## Réaliser la workstation

### 1. Audit

```powershell
.\install.ps1 -Mode Audit
```

### 2. Plan core sans OpenClaw

```powershell
.\install.ps1 `
  -Mode Apply `
  -InstallDevOps `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateHardware `
  -PlanOnly
```

### 3. Convergence core

```powershell
.\install.ps1 `
  -Mode Apply `
  -InstallDevOps `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateHardware
```

### 4. Validation

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

### `-FullInstall`

Le code actuel définit `-FullInstall` comme un raccourci qui active **DevOps + validations WSL/matériel + installation et validation OpenClaw/OpenRouter**.

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

Utiliser ce raccourci lorsque ce périmètre complet est souhaité. Sinon, utiliser le parcours core et ajouter OpenClaw séparément.

Le parcours détaillé est [`docs/20_RUNBOOK_OPERATIONNEL.md`](docs/20_RUNBOOK_OPERATIONNEL.md).

## Résultat attendu

La workstation est prête lorsque :

```text
plan cohérent
+
convergence réussie
+
Windows qualifié
+
matériel qualifié
+
WSL2 conforme
+
stack DevOps conforme
+
idempotence démontrée
+
preuves exploitables
+
sauvegarde vérifiée
```

OpenClaw s'ajoute à ces critères lorsque le périmètre choisi l'inclut, avec une session CLI WezTerm Windows-native cohérente avec le runtime installé.

Checklist : [`docs/24_CRITERES_ACCEPTATION.md`](docs/24_CRITERES_ACCEPTATION.md).

## Principes de sécurité et de stabilité

Le projet conserve les mécanismes essentiels de Windows, distingue les actions automatiques des décisions humaines et évite les changements non qualifiés. Les versions reproductibles viennent des contrats du dépôt, pas d'un `latest` Internet pris automatiquement.

Le détail des limites et des opérations de reprise est documenté dans les guides spécialisés.

## Documentation officielle

Le README est volontairement synthétique. Le portail complet est [`docs/README.md`](docs/README.md).

| Besoin | Document |
| --- | --- |
| Architecture | [`docs/00_ARCHITECTURE.md`](docs/00_ARCHITECTURE.md) |
| Installation Windows | [`docs/01_INSTALLATION_WINDOWS.md`](docs/01_INSTALLATION_WINDOWS.md) |
| WSL2 | [`docs/06_WSL2.md`](docs/06_WSL2.md) |
| Guide WSL2 pédagogique | [`docs/16_WSL2_GUIDE_COMPLET.md`](docs/16_WSL2_GUIDE_COMPLET.md) |
| Stack DevOps et terminal WezTerm | [`docs/07_DEVOPS_STACK.md`](docs/07_DEVOPS_STACK.md) |
| Orchestration | [`docs/14_ORCHESTRATION.md`](docs/14_ORCHESTRATION.md) |
| Vue consolidée | [`docs/18_GUIDE_MAITRE.md`](docs/18_GUIDE_MAITRE.md) |
| Runbook opérationnel | [`docs/20_RUNBOOK_OPERATIONNEL.md`](docs/20_RUNBOOK_OPERATIONNEL.md) |
| Référence des commandes | [`docs/21_REFERENCE_COMMANDES.md`](docs/21_REFERENCE_COMMANDES.md) |
| Troubleshooting | [`docs/22_TROUBLESHOOTING.md`](docs/22_TROUBLESHOOTING.md) |
| Sources de vérité | [`docs/23_SOURCES_DE_VERITE.md`](docs/23_SOURCES_DE_VERITE.md) |
| Critères d'acceptation | [`docs/24_CRITERES_ACCEPTATION.md`](docs/24_CRITERES_ACCEPTATION.md) |
| Backup / restore | [`docs/10_BACKUP_RESTORE.md`](docs/10_BACKUP_RESTORE.md) |
| Reconstruction après incident | [`docs/13_RUNBOOK_REINSTALLATION.md`](docs/13_RUNBOOK_REINSTALLATION.md) |
| OpenClaw/OpenRouter et CLI WezTerm | [`docs/19_OPENCLAW_OPENROUTER_WINDOWS.md`](docs/19_OPENCLAW_OPENROUTER_WINDOWS.md) |

La documentation active décrit **l'état actuel**. `CHANGELOG.md` et Git conservent l'historique.

## Organisation du dépôt

```text
Windows_11_Pro_Custom/
├── README.md
├── START_MENU.cmd
├── menu.ps1
├── install.ps1
├── update.ps1
├── config/
├── manifests/
├── scripts/
├── docs/
├── logs/
├── reports/
└── .github/workflows/
```

En cas de divergence, consulter [`docs/23_SOURCES_DE_VERITE.md`](docs/23_SOURCES_DE_VERITE.md) : la documentation doit refléter l'implémentation et les contrats actuels.