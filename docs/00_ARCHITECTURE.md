# Architecture — Windows 11 Pro Custom

Ce document définit l'architecture active de la workstation : **où vit chaque composant, quel environnement l'exécute et quelles frontières doivent rester stables**.

Pour une vue courte : [`18_GUIDE_MAITRE.md`](18_GUIDE_MAITRE.md). Pour le parcours d'exécution : [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).

## Vue d'ensemble

```text
                         Windows 11 Pro
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
 desktop / pilotes       VS Code Windows          WezTerm
 PowerShell / WinGet            │                    │
 Windows Update                 │            ┌───────┼────────┐
                               │            │       │        │
                               ▼            ▼       ▼        ▼
                              WSL2        Ubuntu   PS7    OpenClaw
                               │          DevOps          / clawops
                               │            │                │
                               └────────────┤                │
                                            ▼                ▼
                                      Linux DevOps     D:\AI\OpenClaw
                                      Docker / K8s     Windows-native
                                      Terraform        control-plane
                                      Ansible / AWS
```

La séparation de responsabilités est :

```text
Windows  -> hôte, applications, pilotes, administration et runtime WSL
Ubuntu   -> backend Linux DevOps et workspaces Linux
WezTerm  -> point d'entrée vers les contextes appropriés
OpenClaw -> extension IA Windows-native, optionnelle
```

Une interface terminal commune ne transforme pas ces environnements en un runtime unique.

## Stockage

```text
C: NTFS
└── Windows 11 Pro et applications système

D: NTFS
├── données
├── D:\WSL\Ubuntu-DevOps
├── D:\AI\OpenClaw
├── ISO
└── exports
```

Ubuntu utilise ext4 dans son VHDX WSL2 stocké sous `D:\WSL\Ubuntu-DevOps`.

Les projets Linux actifs restent dans :

```text
~/projects
~/labs
~/repositories
```

`/mnt/c` et `/mnt/d` servent d'accès aux fichiers Windows, pas de racines quotidiennes aux projets Linux.

Guide : [`03_STOCKAGE.md`](03_STOCKAGE.md).

## Windows et Ubuntu

Windows reste l'hôte pour l'expérience desktop, PowerShell 7, VS Code, WezTerm, les applications Windows et le runtime WSL.

Ubuntu 26.04 reste le backend Linux DevOps pour :

```text
Bash / Git
Docker / Compose / Buildx
kubectl / Helm / Minikube / kind
Terraform / Ansible
AWS CLI / GitHub CLI
outils qualité
```

Guide : [`06_WSL2.md`](06_WSL2.md).

## WezTerm : un point d'entrée, trois contextes

La source versionnée est `config/wezterm/wezterm.lua`.

```text
WezTerm
├── Ubuntu DevOps (WSL2)          <- profil par défaut
├── PowerShell 7                  <- administration Windows
└── OpenClaw / clawops (Windows)  <- CLI IA Windows-native
```

Le profil Ubuntu exécute les outils Linux dans WSL2. Le profil PowerShell reste le contexte Windows général.

Le profil OpenClaw ouvre PowerShell 7 sous Windows, prépare uniquement la session terminal avec les chemins et variables OpenClaw déjà gérés par la workstation, puis vérifie la disponibilité de `openclaw` et `clawops`.

Il ne remplace ni l'installation ni la validation OpenClaw. `scripts/windows/31_wezterm.ps1` vérifie le contrat des trois profils et la conformité de la configuration utilisateur.

Guide : [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md).

## VS Code

```text
VS Code Windows
      ↓
extension WSL
      ↓
Ubuntu
      ↓
projet sous /home/<user>/...
      ↓
outils Linux du projet
```

VS Code reste une application Windows tandis que le runtime des projets Linux reste dans Ubuntu.

## OpenClaw/OpenRouter

L'intégration optionnelle vit sous :

```text
D:\AI\OpenClaw
```

Répartition des responsabilités :

```text
Windows_11_Pro_Custom
└── hôte + stockage + WSL2 + WezTerm + validation d'intégration

openclaw_openrouter
└── runtime OpenClaw + clawops + logique fonctionnelle IA
```

Le profil WezTerm OpenClaw fournit un accès CLI au runtime déjà installé sans déplacer OpenClaw vers WSL2.

Guide : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

## Orchestration

```text
état réel
   ↓
Audit / Verify
   ↓
plan factuel
   ↓
Apply sur les écarts
   ↓
re-Verify
   ↓
logs / rapports / verdict
```

`install.ps1` est le point d'entrée technique principal. `menu.ps1` est le point d'entrée humain.

Guides : [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) et [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md).

## Sources de vérité

| Besoin | Source principale |
| --- | --- |
| WSL version/emplacement | `config/wsl/runtime-contract.json` |
| Ressources WSL | `config/wsl/*.wslconfig` |
| Versions DevOps | `config/devops/tool-versions.env` |
| Terminal WezTerm | `config/wezterm/wezterm.lua` |
| Déploiement WezTerm | `scripts/windows/31_wezterm.ps1` |
| Applications Windows | `manifests/winget/apps-core.json` |
| Pin OpenClaw | `config/openclaw/control-plane.json` |
| Orchestration | `install.ps1` + `scripts/core/runtime.psm1` |
| Interface humaine | `menu.ps1` |

La hiérarchie complète est définie dans [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

## Objectifs architecturaux

1. **Reproductibilité** — reconstruire la workstation sans mémoire implicite.
2. **Séparation des responsabilités** — Windows, WSL2, terminal et OpenClaw gardent leurs rôles.
3. **Performance I/O** — les projets Linux travaillent sur ext4 dans WSL2.
4. **Idempotence** — un composant conforme ne doit pas être réinstallé sans raison.
5. **Observabilité** — l'état et les validations restent explicables.
6. **Pédagogie** — la documentation décrit l'état courant plutôt que l'historique du dépôt.
