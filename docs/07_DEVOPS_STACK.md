# Stack DevOps et expérience terminal

Ce guide décrit la chaîne Linux DevOps de `Windows_11_Pro_Custom` et son accès depuis Windows. OpenClaw/OpenRouter est un projet externe ; sa frontière est décrite dans [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

## Frontière d'exécution

```text
Windows 11 Pro
├── WezTerm
├── PowerShell 7
└── VS Code Windows

Ubuntu WSL2
├── Bash / Git
├── Docker / Compose / Buildx
├── kubectl / Helm / Minikube / kind
├── Terraform / Ansible
├── AWS CLI / GitHub CLI
└── outils qualité
```

Les projets Linux restent sous `~/projects`, `~/labs` ou `~/repositories`. `/mnt/c` et `/mnt/d` servent aux échanges, pas de racines quotidiennes aux projets Linux.

## Installation et validation DevOps

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
.\install.ps1 -Mode Verify -ValidateWsl -ValidateDevOps
```

Les versions reproductibles viennent de `config/devops/tool-versions.env`.

## WezTerm

La source de vérité est `config/wezterm/wezterm.lua`. Le contrat courant expose exactement deux contextes :

```text
Ubuntu DevOps (WSL2) <- profil par défaut
PowerShell 7         <- administration Windows
```

`scripts/windows/31_wezterm.ps1` vérifie ce contrat, compare la configuration versionnée à `%USERPROFILE%\.wezterm.lua` et refuse les hooks spécifiques au projet externe OpenClaw/`clawops`.

```text
Audit  -> observer
Apply  -> converger
Verify -> confirmer
```

Validation WezTerm :

```powershell
.\install.ps1 -Mode Verify
```

## Shell Bash géré

Le profil Linux est installé sous `~/.config/windows11-pro-custom/devops.sh` et intégré à `~/.bashrc` avec des bornes gérées pour préserver l'idempotence. Les personnalisations locales peuvent rester dans `~/.config/windows11-pro-custom/local.sh`.

L'ergonomie peut inclure Starship, fzf, zoxide, eza, bat, fd et ripgrep.

## VS Code et WSL2

```text
VS Code Windows
      ↓
WSL
      ↓
Ubuntu
      ↓
projet sous /home/<user>/...
```

Le terminal intégré et les extensions du projet utilisent ainsi le même environnement Linux que WezTerm `Ubuntu DevOps (WSL2)`.

## Règle à retenir

```text
Windows = hôte et administration Windows
Ubuntu  = backend et projets Linux DevOps
WezTerm = routeur Ubuntu / PowerShell 7
VS Code = UI Windows reliée aux projets WSL2
```

L'installation et la configuration OpenClaw/OpenRouter appartiennent exclusivement au dépôt `mathiasseguincadiche/openclaw_openrouter` et ne sont pas des fonctions de ce dépôt.
