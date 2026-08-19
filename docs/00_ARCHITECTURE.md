# Architecture — Windows 11 Pro Custom

Ce document définit l'architecture active de la workstation : **où vit chaque composant, quel environnement l'exécute et quelles frontières doivent rester stables**.

Pour une vue courte : [`18_GUIDE_MAITRE.md`](18_GUIDE_MAITRE.md). Pour le parcours d'exécution : [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).

## Vue d'ensemble

```text
                         Windows 11 Pro
                              │
        ┌─────────────────────┼─────────────────────────┐
        │                     │                         │
        ▼                     ▼                         ▼
 desktop / pilotes       VS Code Windows        Windows Terminal
 PowerShell / WinGet            │                ┌──────┴──────┐
 Windows Update                 │                │             │
                               ▼                ▼             ▼
                              WSL2       PowerShell 7       Ubuntu
                               │           DevOps            WSL2
                               └───────────────────────────────┤
                                                               ▼
                                                         Linux DevOps
                                                         Docker / K8s
                                                         Terraform
                                                         Ansible / AWS
```

La séparation de responsabilités est :

```text
Windows          -> hôte, applications, pilotes, administration et runtime WSL
Ubuntu           -> backend Linux DevOps et workspaces Linux
Windows Terminal -> point d'entrée vers PowerShell 7 DevOps et Ubuntu DevOps
VS Code          -> interface Windows reliée aux projets WSL2
```

## Stockage

```text
C: NTFS
└── Windows 11 Pro et applications système

E: NTFS
├── données
├── E:\WSL\Ubuntu-DevOps
├── ISO
└── exports
```

Ubuntu utilise ext4 dans son VHDX WSL2 stocké sous `E:\WSL\Ubuntu-DevOps`.

Les projets Linux actifs restent dans :

```text
~/projects
~/labs
~/repositories
```

`/mnt/c` et `/mnt/e` restent accessibles pour des échanges ponctuels avec Windows, mais sont **interdits comme racines de projets ou de workspaces DevOps**. Le VHDX WSL2 peut être physiquement stocké sur `E:` sans que `/mnt/e` devienne pour autant un filesystem de travail Linux.

Guide : [`03_STOCKAGE.md`](03_STOCKAGE.md).

## Windows et Ubuntu

Windows reste l'hôte pour l'expérience desktop, PowerShell 7, VS Code, Windows Terminal, les applications Windows et le runtime WSL.

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

## Windows Terminal : un point d'entrée, deux contextes

Les sources versionnées sont :

```text
config/windows-terminal/profiles.fragment.json
config/windows-terminal/actions.json
config/windows-terminal/starship.windows.toml
```

Le contrat courant expose deux profils gérés :

```text
Windows Terminal
├── PowerShell 7 - DevOps <- profil par défaut
└── Ubuntu - DevOps       <- distribution Ubuntu WSL2
```

Raccourcis :

```text
Ctrl+Shift+1 -> PowerShell 7 - DevOps
Ctrl+Shift+2 -> Ubuntu - DevOps
Ctrl+Shift+O -> PowerShell + Ubuntu en panneaux
```

Le profil Ubuntu exécute les outils Linux dans la distribution `Ubuntu`. Il ne remplace pas le gestionnaire Bash du dépôt : `scripts/wsl/manage-devops-terminal.sh` et `scripts/wsl/manage-shell-profile.sh` restent propriétaires de Bash, Starship Linux et des outils ergonomiques WSL.

`scripts/windows/31_windows_terminal.ps1` vérifie et fait converger le contrat Windows Terminal avec les modes `Audit`, `Apply`, `Verify` et `Rollback`. Il sauvegarde l'état initial des fichiers qu'il possède avant la première mutation et ne réinstalle pas lui-même les applications.

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

## Projets externes

OpenClaw/OpenRouter n'est pas une brique de cette architecture. Le projet autonome `mathiasseguincadiche/openclaw_openrouter` peut être utilisé sur la même machine, mais il possède sa propre installation, sa propre configuration et ses propres validations.

`Windows_11_Pro_Custom` ne clone pas, ne déclenche pas et ne valide pas ce projet externe.

La frontière est documentée dans [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

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

La phase applicative installe Windows Terminal, PowerShell 7, Starship et la Nerd Font via le manifeste WinGet ; WSL2 et son utilisateur sont ensuite provisionnés ; enfin la phase « Poste de travail » applique la configuration Windows Terminal. Cette séquence évite qu'un script de configuration duplique l'installation des dépendances.

Guides : [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) et [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md).

## Sources de vérité

| Besoin | Source principale |
| --- | --- |
| WSL version/emplacement | `config/wsl/runtime-contract.json` |
| Ressources WSL | `config/wsl/*.wslconfig` |
| Versions DevOps | `config/devops/tool-versions.env` |
| Windows Terminal | `config/windows-terminal/` |
| Déploiement Windows Terminal | `scripts/windows/31_windows_terminal.ps1` |
| Shell terminal Ubuntu | `config/wsl/bashrc.d/devops.sh` + `config/wsl/starship.toml` |
| Applications Windows | `manifests/winget/apps-core.json` |
| Orchestration | `install.ps1` + `scripts/core/runtime.psm1` |
| Interface humaine | `menu.ps1` |

La hiérarchie complète est définie dans [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

## Objectifs architecturaux

1. **Reproductibilité** — reconstruire la workstation sans mémoire implicite.
2. **Séparation des responsabilités** — Windows, WSL2, terminal et projets externes gardent leurs rôles.
3. **Performance I/O** — les projets Linux travaillent sur ext4 dans WSL2.
4. **Idempotence** — un composant conforme ne doit pas être réinstallé sans raison.
5. **Observabilité** — l'état et les validations restent explicables.
6. **Pédagogie** — la documentation décrit l'état courant plutôt que l'historique du dépôt.
