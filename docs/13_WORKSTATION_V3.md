# Workstation DevOps — VS Code, WezTerm, PowerShell et environnement WSL

## Objectif

Le poste conserve une frontière claire :

- Windows 11 Pro héberge VS Code, WezTerm, PowerShell 7 et les applications graphiques ;
- Ubuntu WSL2 héberge Docker, Kubernetes, Terraform, AWS CLI, Ansible et les outils de qualité ;
- les dépôts Linux restent sous `/home/<user>/projects` ;
- `C:` et `D:` restent NTFS.

## PowerShell 7

Le socle installe la version stable actuelle de PowerShell 7 via :

```text
Microsoft.PowerShell
```

Commande quotidienne :

```powershell
pwsh
```

Vérifier :

```powershell
$PSVersionTable
```

Windows PowerShell 5.1 reste présent pour la compatibilité des composants historiques Windows. PowerShell 7 devient le shell moderne recommandé pour le travail quotidien.

VS Code expose deux profils de terminal Windows :

```text
Ubuntu WSL      profil par défaut pour le DevOps
PowerShell 7    shell Windows moderne disponible à la demande
```

## VS Code

Configuration versionnée :

```text
config/vscode/settings.json
config/vscode/extensions.txt
config/vscode/extensions-wsl.txt
```

Extensions principales :

- WSL — `ms-vscode-remote.remote-wsl` ;
- Remote - SSH — `ms-vscode-remote.remote-ssh` ;
- SFTP / FTP — `Natizyskunk.sftp` ;
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

## Client OpenSSH Windows

Remote - SSH a besoin d'un client SSH local fiable. Windows 11 ne doit donc pas être supposé posséder OpenSSH Client sur une installation fraîche.

Le dépôt gère explicitement la capacité Windows :

```text
OpenSSH.Client~~~~0.0.1.0
```

avec :

```powershell
.\scripts\windows\32_openssh_client.ps1 -Mode Audit
.\scripts\windows\32_openssh_client.ps1 -Mode Apply
.\scripts\windows\32_openssh_client.ps1 -Mode Verify
.\scripts\windows\32_openssh_client.ps1 -Mode Rollback
```

Le premier `Apply` enregistre si le client était déjà installé. Le rollback ne le supprime que si le dépôt l'avait lui-même ajouté.

Le **serveur OpenSSH Windows n'est pas installé** : le besoin de cette workstation est de se connecter vers des serveurs distants, pas d'exposer Windows comme serveur SSH.

Vérifier :

```powershell
ssh -V
Get-Command ssh.exe
```

## VS Code Remote - SSH

Remote - SSH sert à travailler **directement sur le filesystem d'un serveur distant**.

Le client est exécuté côté Windows. Sa configuration de référence est donc :

```text
%USERPROFILE%\.ssh\config
%USERPROFILE%\.ssh\id_ed25519
%USERPROFILE%\.ssh\id_ed25519.pub
```

Exemple versionné :

```text
config/vscode/ssh-config.example
```

Exemple :

```text
Host devops-server
    HostName server.example.com
    User replace-me
    Port 22
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

Dans ce fichier Windows OpenSSH, `~` correspond au HOME Windows de l'utilisateur.

### Créer la clé Windows pour Remote - SSH

Dans PowerShell 7 :

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.ssh" | Out-Null
ssh-keygen -t ed25519 -a 64 -f "$env:USERPROFILE\.ssh\id_ed25519" -C "windows-vscode-remote-ssh"
```

La clé privée reste :

```text
%USERPROFILE%\.ssh\id_ed25519
```

Ne jamais la versionner.

Connexion dans VS Code :

```text
Ctrl+Shift+P
Remote-SSH: Connect to Host...
devops-server
```

Le projet reste alors sur le serveur distant et VS Code Server s'exécute côté serveur.

## SSH depuis Ubuntu WSL

Le client Linux est distinct du client OpenSSH Windows.

Le bootstrap DevOps installe `openssh-client` dans Ubuntu. Si les commandes Linux `ssh`, `scp`, `rsync` ou SFTP ont besoin d'une clé, créer une **clé Linux séparée** :

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -a 64 -f ~/.ssh/id_ed25519 -C "wsl-devops"
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

Cette séparation évite de dépendre d'un chemin `/mnt/c/...` pour une clé privée Linux et rend les permissions plus simples à comprendre.

Les deux clés peuvent naturellement être autorisées sur le même serveur distant si nécessaire.

## VS Code SFTP / FTP

L'extension `Natizyskunk.sftp` est installée côté Windows et dans l'hôte WSL afin de fonctionner avec les deux types de workspace.

Exemple sécurisé :

```text
config/vscode/sftp.example.json
```

Dans un projet réel, l'extension utilise généralement :

```text
.vscode/sftp.json
```

Ce fichier est ignoré par le dépôt principal afin d'éviter la publication accidentelle de secrets.

### Workspace Windows

Si l'extension tourne côté Windows :

```text
privateKeyPath = ~/.ssh/id_ed25519
```

référence la clé du HOME Windows.

### Workspace WSL

Si l'extension tourne dans l'hôte WSL :

```text
privateKeyPath = ~/.ssh/id_ed25519
```

référence la clé Linux située sous `/home/<user>/.ssh/`.

Préférence :

```text
SFTP + clé SSH
```

plutôt que :

```text
FTP + mot de passe
```

Pour SFTP :

```json
{
  "protocol": "sftp",
  "port": 22,
  "privateKeyPath": "~/.ssh/id_ed25519"
}
```

Pour un serveur imposant FTP, utiliser au minimum FTPS/TLS lorsque le serveur le prend en charge. Ne jamais committer un champ `password` dans Git.

### SFTP ou Remote - SSH ?

```text
Remote - SSH
    code et outils sur le serveur distant
    environnement distant complet
    recommandé pour administration / développement distant

SFTP
    fichiers locaux ou WSL synchronisés vers le serveur
    utile pour hébergement web / transferts ciblés
```

## WezTerm

Configuration versionnée :

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

## Outils qualité IaC

La workstation installe et vérifie :

- terraform-docs `v0.24.0` ;
- actionlint `v1.7.12` ;
- yq `v4.53.3` ;
- TFLint `v0.64.0`.

Les archives sont vérifiées par SHA-256. actionlint et TFLint utilisent également GitHub Artifact Attestations lorsque le projet les publie.

## Workflow complet après réinstallation

```powershell
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Apply
```

Lancer Ubuntu une première fois et créer l'utilisateur Linux, puis :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
wsl --shutdown
.\install.ps1 -Mode Verify -ValidateWsl -ValidateDevOps
```

Verdict WSL2 V6 attendu :

```text
VERDICT: V6 WSL2 PLATFORM READY
```
