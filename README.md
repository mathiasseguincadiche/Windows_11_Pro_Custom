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
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
 desktop / sécurité      VS Code Windows          WezTerm
 pilotes / gaming               │                    │
 PowerShell / WinGet            │            ┌───────┼────────┐
 Windows Update                 │            │       │        │
                               │            ▼       ▼        ▼
                               │         Ubuntu   PowerShell  OpenClaw
                               │          WSL2       7       / clawops
                               │            │                  │
                               └── WSL ─────┤                  │
                                            ▼                  ▼
                                      Linux DevOps       D:\AI\OpenClaw
                                      Docker / K8s       Windows-native
                                      Terraform          control-plane
                                      Ansible / AWS      état / workspace
```

La séparation fonctionnelle est volontaire :

```text
Windows = hôte, desktop, sécurité, pilotes, administration et capacité d'accueil OpenClaw
Ubuntu  = backend Linux DevOps et workspaces Linux
WezTerm = point d'entrée terminal vers les contextes sans mélanger les runtimes
VS Code = interface Windows reliée aux projets WSL2
```

### WezTerm comme routeur de contextes

WezTerm expose trois profils explicites :

```text
Ubuntu DevOps (WSL2)          -> profil par défaut, Bash et outils Linux
PowerShell 7                  -> administration Windows
OpenClaw / clawops (Windows)  -> CLI IA Windows-native
```

Le profil OpenClaw prépare uniquement **sa session PowerShell** pour retrouver les variables et launchers gérés sous `D:\AI\OpenClaw`, puis vérifie la disponibilité de `openclaw` et `clawops`. Il n'installe rien et ne lance aucune opération métier automatiquement.

Cette règle évite deux erreurs d'architecture : déplacer OpenClaw dans WSL2 uniquement pour l'ergonomie du terminal, ou utiliser les projets Linux depuis un filesystem Windows comme racine quotidienne.

Références : [`docs/07_DEVOPS_STACK.md`](docs/07_DEVOPS_STACK.md) pour l'expérience terminal et [`docs/19_OPENCLAW_OPENROUTER_WINDOWS.md`](docs/19_OPENCLAW_OPENROUTER_WINDOWS.md) pour l'intégration OpenClaw.

## Contrats principaux

### Stockage

```text
C: NTFS -> Windows 11 Pro et composants système
D: NTFS -> données, WSL2, OpenClaw, ISO et exports
```

Ubuntu utilise ext4 **dans son VHDX WSL2** stocké sous :

```text
D:\WSL\Ubuntu-DevOps
```

Les projets Linux actifs restent sous :

```text
~/projects
~/labs
~/repositories
```

et non sous `/mnt/c` ou `/mnt/d` comme racines principales.

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

Ubuntu fournit la chaîne Linux de référence : Docker Engine, Compose/Buildx, Kubernetes CLI, Helm, Minikube, kind, Terraform, Ansible, AWS CLI, GitHub CLI et les outils qualité pilotés par les contrats du dépôt.

### OpenClaw/OpenRouter

OpenClaw est une **extension optionnelle de la workstation**, Windows-native sous :

```text
D:\AI\OpenClaw
```

La frontière de responsabilité est stricte :

```text
Windows_11_Pro_Custom
  -> prépare l'hôte Windows, D:, WezTerm et les frontières WSL2
  -> référence un control-plane approuvé
  -> peut déclencher ce control-plane
  -> valide l'intégration locale

openclaw_openrouter
  -> installe et converge OpenClaw
  -> configure OpenRouter
  -> possède clawops, Gateway, modèles, agents et politiques IA
  -> possède les contrats et procédures du runtime IA
```

**Déclencher le dépôt IA ne transfère pas sa propriété fonctionnelle au dépôt Windows.** `Windows_11_Pro_Custom` ne recopie ni le runtime lock, ni les modèles, ni les agents, ni l'onboarding OpenRouter.

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

## Deux périmètres d'installation

### Workstation core

Le parcours core construit Windows + WSL2 + DevOps sans rendre OpenClaw obligatoire :

```powershell
.\install.ps1 `
  -Mode Apply `
  -InstallDevOps `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateHardware
```

C'est le parcours à utiliser lorsque l'on veut gérer **uniquement la workstation**.

### Agrégation complète avec extension IA

Le raccourci `-FullInstall` conserve son comportement existant : il active la workstation complète puis **délègue** l'installation/validation OpenClaw au control-plane externe approuvé :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

Ce raccourci est une commodité d'orchestration, pas une fusion des deux projets. L'installation complète OpenClaw/OpenRouter reste implémentée et documentée dans `openclaw_openrouter`.

L'extension IA peut aussi être demandée séparément :

```powershell
.\install.ps1 -Mode Apply -InstallOpenClawAI
```

## Parcours recommandé

### 1. Observer

```powershell
.\install.ps1 -Mode Audit
```

### 2. Prévisualiser

Workstation core :

```powershell
.\install.ps1 `
  -Mode Apply `
  -InstallDevOps `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateHardware `
  -PlanOnly
```

Agrégation complète avec OpenClaw :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

### 3. Faire converger

Appliquer le même périmètre sans `-PlanOnly`.

### 4. Prouver la conformité

Workstation :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

Si OpenClaw est utilisé :

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

### 5. Prouver l'idempotence

Recalculer ensuite le même plan. Une workstation stabilisée doit tendre vers `DÉJÀ OK` et ne pas reproposer arbitrairement les mêmes mutations.

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
terminal WezTerm conforme
+
OpenClaw qualifié si utilisé
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
| Intégration facultative OpenClaw/OpenRouter | [`docs/19_OPENCLAW_OPENROUTER_WINDOWS.md`](docs/19_OPENCLAW_OPENROUTER_WINDOWS.md) |
| Runbook opérationnel | [`docs/20_RUNBOOK_OPERATIONNEL.md`](docs/20_RUNBOOK_OPERATIONNEL.md) |
| Référence des commandes | [`docs/21_REFERENCE_COMMANDES.md`](docs/21_REFERENCE_COMMANDES.md) |
| Troubleshooting | [`docs/22_TROUBLESHOOTING.md`](docs/22_TROUBLESHOOTING.md) |
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
├── config/        # contrats versionnés
├── manifests/     # catalogues déclaratifs
├── scripts/       # implémentation
├── docs/          # documentation officielle
├── logs/          # preuves d'exécution
├── reports/       # rapports structurés
└── .github/workflows/
```

En cas de divergence entre texte, scripts et état réel, suivre [`docs/23_SOURCES_DE_VERITE.md`](docs/23_SOURCES_DE_VERITE.md).