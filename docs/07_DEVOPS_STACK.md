# Stack DevOps et terminal Linux

## Principe

Windows héberge l'interface graphique, les applications desktop et l'administration de l'hôte. Ubuntu WSL2 héberge la chaîne Linux DevOps.

Docker Desktop n'est pas requis : Docker Engine tourne directement dans Ubuntu.

Les projets Linux restent dans le filesystem WSL :

```text
/home/<user>/projects
/home/<user>/labs
/home/<user>/repositories
```

et non dans `/mnt/c` ou `/mnt/d` comme racines de travail principales.

---

## Stack installée

### Conteneurs

- Docker Engine ;
- Docker CLI ;
- containerd ;
- Docker Buildx ;
- Docker Compose plugin.

Docker fonctionne avec systemd dans WSL2.

Le daemon utilise le driver de logs `local` avec rotation afin de limiter la croissance incontrôlée du VHDX.

### Kubernetes

- kubectl ;
- Helm ;
- Minikube ;
- kind.

Exemple Minikube :

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
- yq ;
- terraform-docs ;
- actionlint ;
- TFLint.

Les outils sensibles à la reproductibilité utilisent les versions validées par le dépôt plutôt qu'une installation `latest` arbitraire.

---

## Installation / convergence

Une fois WSL2 et l'utilisateur Ubuntu disponibles :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

L'orchestrateur vérifie l'état avant d'installer ce qui manque.

Après installation de Docker et ajout au groupe `docker` :

```powershell
wsl --shutdown
```

Puis dans Ubuntu :

```bash
docker info
docker run --rm hello-world
```

L'appartenance au groupe `docker` donne un niveau de privilège élevé dans Linux ; elle est acceptée ici pour l'ergonomie d'une workstation DevOps personnelle.

---

## Terminal quotidien

WezTerm est configuré pour offrir deux environnements clairement séparés :

```text
WezTerm
├── Ubuntu / Bash DevOps   <- profil principal
└── PowerShell 7           <- administration Windows
```

Le but est d'éviter les ambiguïtés du type :

```text
commande Linux lancée dans PowerShell
commande Windows lancée comme si elle était native Linux
projet Linux ouvert depuis un filesystem Windows inadapté
```

---

## Profil Bash

Le dépôt gère un profil shell sous :

```text
~/.config/windows11-pro-custom/devops.sh
```

Il fournit notamment :

- alias Git ;
- alias Docker ;
- alias Kubernetes / Helm ;
- alias Terraform / Ansible / AWS ;
- complétions ;
- environnement cohérent pour les outils CLI.

Le bloc géré dans `~/.bashrc` est borné afin de pouvoir être appliqué plusieurs fois sans duplication.

Une personnalisation locale peut rester dans :

```text
~/.config/windows11-pro-custom/local.sh
```

sans être écrasée par le dépôt.

---

## Outils d'ergonomie CLI

Le profil DevOps peut inclure :

- Starship ;
- fzf ;
- zoxide ;
- eza ;
- bat ;
- fd ;
- ripgrep.

Ces outils améliorent l'ergonomie mais ne remplacent pas les composants DevOps fondamentaux.

---

## VS Code

VS Code reste une application Windows pour l'interface, mais les projets Linux sont ouverts via l'extension WSL.

```text
VS Code Windows
      ↓
Remote / WSL
      ↓
Ubuntu
      ↓
projet dans /home/<user>/...
      ↓
outils Linux du projet
```

Cette architecture permet au terminal intégré, aux extensions WSL et aux outils comme Terraform/Ansible/ShellCheck de fonctionner dans le même environnement que le projet.

Le poste prend aussi en charge :

- Remote - SSH ;
- SFTP/FTP lorsque nécessaire ;
- Container Tools ;
- Kubernetes ;
- Terraform ;
- YAML ;
- GitHub Actions ;
- shell-format / ShellCheck.

Les secrets et configurations personnelles de connexion ne doivent pas être commités.

---

## OpenSSH Client

Le client OpenSSH Windows est géré pour permettre les connexions distantes depuis Windows/VS Code.

Le serveur OpenSSH Windows n'est pas installé par défaut : le projet n'a pas besoin de transformer la workstation en serveur SSH entrant.

---

## Docker et journaux

Les logs de conteneurs doivent rester bornés afin d'éviter une croissance silencieuse du disque virtuel WSL.

Le projet utilise une configuration Docker versionnée avec rotation adaptée à une workstation locale.

---

## Répertoires de travail

Le bootstrap prépare notamment :

```text
~/projects
~/labs
~/repositories
~/scripts
~/workspace
~/backups
```

Ces répertoires restent dans le filesystem Linux.

---

## Validation

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

La validation peut contrôler :

- présence des binaires ;
- versions attendues des outils sensibles ;
- Docker sans sudo selon la politique ;
- service Docker ;
- driver de logs ;
- HOME Linux correct ;
- racines de travail ;
- profil shell ;
- qualité Bash ;
- actionlint ;
- smoke tests IaC.

Voir [`11_VALIDATION.md`](11_VALIDATION.md).

---

## Mise à jour

Les paquets Ubuntu suivent la politique de maintenance du dépôt.

Les outils épinglés ne doivent être mis à jour qu'après modification de la version souhaitée, vérification de l'intégrité et requalification.

Guide : [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

## Règle à retenir

```text
Windows = hôte / UI / administration Windows
Ubuntu  = Linux DevOps
VS Code = pont entre les deux
WezTerm = accès quotidien aux deux univers
```

Cette séparation donne à Windows les avantages d'un vrai poste desktop tout en conservant un environnement Linux natif pour les workflows DevOps.
