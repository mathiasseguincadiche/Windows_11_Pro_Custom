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
 PowerShell / WinGet            │                ┌──┴─────┐
 Windows Update                 │                │        │
                               ▼                ▼        ▼
                              WSL2           Ubuntu    PowerShell 7
                               │             DevOps
                               └───────────────┤
                                               ▼
                                         Linux DevOps
                                         Docker / K8s
                                         Terraform
                                         Ansible / AWS
```

La séparation de responsabilités est :

```text
Windows -> hôte, applications, pilotes, administration et runtime WSL
Ubuntu  -> backend Linux DevOps et workspaces Linux
WezTerm -> point d'entrée vers Ubuntu DevOps et PowerShell 7
VS Code -> interface Windows reliée aux projets WSL2
```

## Stockage

```text
C: NTFS
└── Windows 11 Pro et applications système

D: NTFS
├── données
├── D:\WSL\Ubuntu-DevOps
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

## WezTerm : un point d'entrée, deux contextes

La source versionnée est `config/wezterm/wezterm.lua`.

```text
WezTerm
├── Ubuntu DevOps (WSL2) <- profil par défaut
└── PowerShell 7         <- administration Windows
```

Le profil Ubuntu exécute les outils Linux dans WSL2. Le profil PowerShell reste le contexte Windows général.

`scripts/windows/31_wezterm.ps1` vérifie ce contrat et la conformité de la configuration utilisateur.

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
