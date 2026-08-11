# Stack DevOps WSL2

## Principe

Windows héberge l'interface graphique et les applications desktop. Ubuntu WSL2 héberge la chaîne Linux DevOps. Docker Desktop n'est pas requis.

Les projets exécutés avec les outils Linux restent dans le filesystem WSL :

```text
/home/<user>/projects
```

et non dans `/mnt/c` ou `/mnt/d`.

## Installation

Après installation de WSL2, lancer Ubuntu une première fois afin de créer l'utilisateur Linux. Puis, depuis PowerShell administrateur à la racine du dépôt :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

Le bootstrap principal appelle `scripts/wsl/install-devops.sh`, puis les installateurs qualité et profil shell.

## Outils installés

### Conteneurs

- Docker Engine ;
- Docker CLI ;
- containerd ;
- Docker Buildx ;
- Docker Compose plugin.

Docker est installé depuis le dépôt APT officiel Docker et fonctionne avec systemd dans WSL2.

Le daemon utilise le driver de logs `local` avec rotation définie dans :

```text
config/wsl/docker-daemon.json
```

### Kubernetes

- kubectl ;
- Helm ;
- Minikube ;
- kind.

Pour Minikube sous WSL2 :

```bash
minikube start --driver=docker
```

### Infrastructure / Cloud

- Terraform ;
- AWS CLI v2 ;
- Ansible Core ;
- GitHub CLI.

### Qualité / sécurité

- ShellCheck ;
- shfmt ;
- Trivy ;
- jq ;
- yq `v4.53.3` ;
- terraform-docs `v0.24.0` ;
- actionlint `v1.7.12` ;
- TFLint `v0.64.0`.

Les binaires téléchargés directement sont contrôlés par empreinte SHA-256. actionlint et TFLint utilisent aussi GitHub Artifact Attestations.

## Docker sans sudo

Le bootstrap ajoute l'utilisateur au groupe `docker`. Après l'installation :

```powershell
wsl --shutdown
```

Puis relancer Ubuntu et contrôler :

```bash
docker info
docker run --rm hello-world
```

L'appartenance au groupe `docker` donne un niveau de privilège important sur la machine Linux ; elle est choisie ici pour l'ergonomie d'un poste DevOps personnel.

## Profil shell

Le bootstrap installe :

```text
~/.config/windows11-pro-custom/devops.sh
```

et ajoute un bloc borné dans `~/.bashrc` pour les alias et complétions DevOps.

## Validation V3

```bash
bash ./scripts/wsl/validate-devops.sh
```

Le validateur contrôle notamment :

- tous les binaires DevOps et qualité ;
- Docker accessible sans sudo ;
- service systemd Docker actif ;
- logging driver Docker `local` ;
- HOME Linux hors de `/mnt/c` et `/mnt/d` ;
- répertoires de travail ;
- profil shell ;
- workflows GitHub Actions avec actionlint ;
- smoke test `terraform fmt` / `terraform validate`.

Verdict attendu :

```text
VERDICT: V3 DEVOPS READY
```

## Répertoires créés

```text
~/projects
~/labs
~/repositories
~/scripts
~/workspace
~/backups
```

## Mise à jour

Les composants installés via APT suivent :

```bash
sudo apt update
sudo apt upgrade
```

Les outils binaires épinglés doivent être mis à jour dans le dépôt avec leurs nouvelles empreintes, puis requalifiés par CI avant changement de version.
