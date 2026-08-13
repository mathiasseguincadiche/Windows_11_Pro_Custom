# Stack DevOps et terminal Linux

## Principe

Windows héberge l'interface graphique, les applications desktop et l'administration de l'hôte. Ubuntu WSL2 héberge la chaîne Linux DevOps. OpenClaw et `clawops`, lorsqu'ils sont utilisés, restent Windows-native.

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

WezTerm expose trois contextes clairement séparés :

```text
WezTerm
├── Ubuntu DevOps (WSL2)          <- profil principal et défaut
├── PowerShell 7                  <- administration Windows
└── OpenClaw / clawops (Windows)  <- CLI IA Windows-native
```

Le profil Ubuntu reste le défaut pour Docker, Kubernetes, Terraform, Ansible, AWS et les projets Linux. Le profil PowerShell 7 reste destiné à Windows.

Le profil OpenClaw ouvre lui aussi PowerShell 7 sous Windows. Il recharge dans **cette session uniquement** les variables utilisateur OpenClaw, complète le `PATH` de session avec `D:\AI\OpenClaw\npm-global` et `D:\AI\OpenClaw\venv\Scripts` lorsqu'ils existent, utilise explicitement les launchers Windows `openclaw.cmd` et `clawops.exe`, puis se place sous `D:\AI\OpenClaw`.

Il affiche ensuite si `openclaw` et `clawops` sont disponibles et laisse le terminal interactif à l'utilisateur. Il ne déclenche aucune opération OpenClaw automatiquement et ne réécrit pas l'environnement utilisateur persistant.

Cette organisation évite les ambiguïtés suivantes :

```text
commande Linux lancée dans PowerShell
commande Windows lancée comme si elle était native Linux
OpenClaw déplacé dans WSL2 uniquement pour l'ergonomie du terminal
projet Linux ouvert depuis un filesystem Windows inadapté
```

Le détail de l'intégration OpenClaw est dans [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

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

La configuration WezTerm appartient au composant « poste de travail » vérifié par `install.ps1 -Mode Verify`. Lorsque OpenClaw fait partie du périmètre, sa disponibilité réelle est validée séparément avec `-ValidateOpenClawAI`.

Voir [`11_VALIDATION.md`](11_VALIDATION.md).

---

## Mise à jour

Les paquets Ubuntu suivent la politique de maintenance du dépôt.

Les outils épinglés ne doivent être mis à jour qu'après modification de la version souhaitée, vérification de l'intégrité et requalification.

Guide : [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

## Règle à retenir

```text
Windows = hôte / UI / administration Windows / OpenClaw
Ubuntu  = Linux DevOps
VS Code = pont entre Windows et les projets WSL2
WezTerm = accès quotidien aux contextes séparés
```

Une interface terminal unique ne signifie pas un runtime unique. Chaque outil reste dans l'environnement défini par l'architecture du projet.