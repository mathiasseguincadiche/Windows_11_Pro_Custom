# Workstation V3 — VS Code, WezTerm et environnement WSL

## Objectif

La V3 termine le poste de travail DevOps en conservant une frontière claire :

- Windows 11 Pro héberge VS Code, WezTerm et les applications graphiques ;
- Ubuntu WSL2 héberge Docker, Kubernetes, Terraform, AWS CLI, Ansible et les outils de qualité ;
- les dépôts Linux restent sous `/home/<user>/projects` ;
- `C:` et `D:` restent NTFS.

## VS Code

La configuration versionnée est située dans :

```text
config/vscode/settings.json
config/vscode/extensions.txt
```

Extensions installées par la V3 :

- WSL — `ms-vscode-remote.remote-wsl` ;
- Terraform — `hashicorp.terraform` ;
- Kubernetes — `ms-kubernetes-tools.vscode-kubernetes-tools` ;
- Container Tools — `ms-azuretools.vscode-containers` ;
- YAML — `redhat.vscode-yaml` ;
- GitHub Actions — `github.vscode-github-actions` ;
- ShellCheck — `timonwong.shellcheck` ;
- shell-format — `foxundermoon.shell-format`.

Le terminal intégré par défaut lance Ubuntu via `wsl.exe -d Ubuntu`.

Gestion :

```powershell
.\scripts\windows\30_vscode.ps1 -Mode Audit
.\scripts\windows\30_vscode.ps1 -Mode Apply
.\scripts\windows\30_vscode.ps1 -Mode Verify
.\scripts\windows\30_vscode.ps1 -Mode Rollback
```

Le premier `Apply` sauvegarde le `settings.json` existant et la liste des extensions déjà présentes. Le rollback restaure le fichier initial et ne désinstalle que les extensions ajoutées par le dépôt.

## WezTerm

La configuration versionnée :

```text
config/wezterm/wezterm.lua
```

WezTerm démarre directement :

```text
wsl.exe -d Ubuntu --cd ~
```

Gestion :

```powershell
.\scripts\windows\31_wezterm.ps1 -Mode Audit
.\scripts\windows\31_wezterm.ps1 -Mode Apply
.\scripts\windows\31_wezterm.ps1 -Mode Verify
.\scripts\windows\31_wezterm.ps1 -Mode Rollback
```

## Profil shell WSL

Le profil source est :

```text
config/wsl/bashrc.d/devops.sh
```

Il est copié vers :

```text
~/.config/windows11-pro-custom/devops.sh
```

Le bootstrap ajoute un bloc borné dans `~/.bashrc`. Les alias principaux sont :

```text
k    -> kubectl
h    -> helm
tf   -> terraform
dc   -> docker compose
gst  -> git status --short --branch
```

Les complétions kubectl et Helm sont activées si les commandes sont disponibles.

## Outils qualité IaC

La V3 installe et vérifie :

- terraform-docs `v0.24.0` ;
- actionlint `v1.7.12` ;
- yq `v4.53.3` ;
- TFLint `v0.64.0`.

Les archives sont vérifiées par SHA-256. actionlint et TFLint utilisent également GitHub Artifact Attestations lorsque le projet les publie.

## Orchestration

Configuration du poste Windows :

```powershell
.\scripts\bootstrap\10_workstation.ps1 -Mode Apply
```

Qualification Windows V3 :

```powershell
.\scripts\bootstrap\11_validate_v3.ps1
```

Qualification Linux V3 :

```bash
bash ./scripts/wsl/validate-devops.sh
```

## Workflow complet après réinstallation

```powershell
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Apply
```

Lancer Ubuntu une première fois et créer l'utilisateur Linux, puis :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
wsl --shutdown
.\install.ps1 -Mode Verify -ValidateDevOps
```

Le poste n'est considéré V3 READY que si le validateur Windows et le validateur Linux terminent tous les deux sans `KO`.
