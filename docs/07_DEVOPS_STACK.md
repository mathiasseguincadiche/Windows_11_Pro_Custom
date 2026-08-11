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
.\scripts\bootstrap\08_devops.ps1 -Distribution Ubuntu
```

Ou directement depuis Ubuntu :

```bash
bash ./scripts/wsl/install-devops.sh
```

## Outils installés

### Conteneurs

- Docker Engine ;
- Docker CLI ;
- containerd ;
- Docker Buildx ;
- Docker Compose plugin.

Docker est installé depuis le dépôt APT officiel Docker et fonctionne avec systemd dans WSL2.

### Kubernetes

- kubectl ;
- Helm ;
- Minikube ;
- kind.

Le script détermine dynamiquement la branche mineure Kubernetes stable pour configurer `pkgs.k8s.io`. `kind` est épinglé par défaut sur une version stable définie dans le script et peut être surchargé par `KIND_VERSION`.

Pour Minikube sous WSL2, le driver recommandé pour cette architecture est Docker :

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
- jq.

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

## Validation

```bash
bash ./scripts/wsl/validate-devops.sh
```

Le verdict attendu est :

```text
VERDICT: STACK DEVOPS READY
```

Le contrôle vérifie également que le HOME Linux ne se trouve pas sous `/mnt/c` ou `/mnt/d`.

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

Les composants installés via APT suivent ensuite le mécanisme normal :

```bash
sudo apt update
sudo apt upgrade
```

AWS CLI, Minikube et kind sont des installations binaires et doivent être mis à jour via leurs installateurs ou en relançant le bootstrap après validation d'une nouvelle version.
