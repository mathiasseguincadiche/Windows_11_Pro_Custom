# Stack DevOps et expérience terminal

Ce guide décrit **la chaîne Linux DevOps et la manière d'y accéder au quotidien depuis Windows**.

Il ne documente pas le fonctionnement métier d'OpenClaw. Pour l'intégration IA Windows-native : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

## Frontière d'exécution

```text
Windows 11 Pro
├── WezTerm
├── PowerShell 7
├── VS Code Windows
└── OpenClaw / clawops si utilisés

Ubuntu WSL2
├── Bash / Git
├── Docker
├── Kubernetes
├── Terraform / Ansible
├── AWS / GitHub CLI
└── outils qualité
```

Les projets Linux restent dans le filesystem WSL2 :

```text
/home/<user>/projects
/home/<user>/labs
/home/<user>/repositories
```

`/mnt/c` et `/mnt/d` servent aux échanges avec Windows, pas de racines quotidiennes aux projets Linux.

Docker Desktop n'est pas requis : Docker Engine tourne directement dans Ubuntu.

---

## Stack DevOps

### Conteneurs

- Docker Engine ;
- Docker CLI ;
- containerd ;
- Docker Buildx ;
- Docker Compose plugin.

Docker fonctionne avec systemd dans WSL2. Sa configuration de logs est gérée afin de limiter la croissance inutile du VHDX.

### Kubernetes

- kubectl ;
- Helm ;
- Minikube ;
- kind.

Exemple local :

```bash
minikube start --driver=docker
```

### Infrastructure et Cloud

- Terraform ;
- Ansible Core ;
- AWS CLI v2 ;
- GitHub CLI.

### Qualité et sécurité

- ShellCheck ;
- shfmt ;
- Trivy ;
- jq ;
- yq ;
- terraform-docs ;
- actionlint ;
- TFLint.

Les outils sensibles à la reproductibilité suivent les versions validées par `config/devops/tool-versions.env` lorsqu'une version est explicitement épinglée.

---

## Installation et convergence DevOps

Une fois WSL2 et l'utilisateur Ubuntu disponibles :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

L'orchestrateur observe l'état puis installe ou corrige uniquement ce qui manque dans le périmètre demandé.

Validation :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl -ValidateDevOps
```

Après certains changements Linux nécessitant une nouvelle session WSL, utiliser le mécanisme prévu par le guide WSL2 puis relancer la même validation.

Référence WSL2 : [`06_WSL2.md`](06_WSL2.md).

---

# WezTerm — point d'entrée terminal de la workstation

WezTerm ne constitue pas un quatrième runtime. Il sert de **routeur explicite vers les environnements déjà définis par l'architecture**.

La configuration de référence est :

```text
config/wezterm/wezterm.lua
```

Le contrat courant expose exactement trois contextes :

```text
WezTerm
├── Ubuntu DevOps (WSL2)          <- défaut
├── PowerShell 7                  <- Windows
└── OpenClaw / clawops (Windows)  <- IA Windows-native
```

## Profil `Ubuntu DevOps (WSL2)`

C'est le profil par défaut.

Il ouvre Bash dans la distribution `Ubuntu` et doit être utilisé pour :

- les projets sous `~/projects`, `~/labs`, `~/repositories` ;
- Docker et Kubernetes ;
- Terraform et Ansible ;
- AWS CLI et GitHub CLI côté Linux ;
- les scripts Bash et outils qualité Linux.

Ce profil matérialise la règle : **les workloads Linux restent dans Linux**.

## Profil `PowerShell 7`

Ce profil ouvre PowerShell 7 sur l'hôte Windows.

Il sert notamment à :

- `install.ps1` ;
- `update.ps1` ;
- l'administration Windows ;
- les commandes et outils réellement Windows-native.

## Profil `OpenClaw / clawops (Windows)`

Ce profil ouvre lui aussi PowerShell 7 sous Windows, mais prépare la session pour le runtime IA installé sous :

```text
D:\AI\OpenClaw
```

La préparation reste **locale à la session WezTerm ouverte** :

- recharge les variables utilisateur OpenClaw pertinentes ;
- rend accessibles les répertoires CLI gérés sous `D:\AI\OpenClaw` lorsqu'ils existent ;
- privilégie les launchers Windows `openclaw.cmd` et `clawops.exe` ;
- se positionne sur la racine OpenClaw lorsqu'elle existe ;
- indique si `openclaw` et `clawops` sont disponibles.

Le profil ne réalise pas l'installation OpenClaw et ne lance pas automatiquement une opération métier. L'installation et la qualification restent sous la responsabilité de l'intégration OpenClaw.

Cette séparation évite de déplacer OpenClaw dans WSL2 uniquement pour obtenir une expérience CLI homogène.

Détails : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

## Contrat WezTerm et convergence

`scripts/windows/31_wezterm.ps1` vérifie que la configuration source conserve :

```text
Ubuntu DevOps (WSL2)          comme défaut
PowerShell 7                  comme contexte Windows
OpenClaw / clawops (Windows)  comme contexte IA Windows-native
```

Il compare ensuite la configuration versionnée à `%USERPROFILE%\.wezterm.lua`.

Le composant est géré avec les mêmes intentions que le reste de la workstation :

```text
Audit -> observer
Apply -> converger
Verify -> confirmer
```

La validation générale de la workstation couvre la configuration WezTerm. `-ValidateOpenClawAI` reste nécessaire pour prouver que le runtime OpenClaw derrière le profil existe réellement.

---

## Shell Bash géré

Le profil Linux versionné est installé sous :

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

Les personnalisations locales peuvent rester dans :

```text
~/.config/windows11-pro-custom/local.sh
```

sans être remplacées par le dépôt.

### Ergonomie CLI

Le profil peut intégrer :

- Starship ;
- fzf ;
- zoxide ;
- eza ;
- bat ;
- fd ;
- ripgrep.

Ces outils améliorent l'usage quotidien mais ne remplacent pas les composants DevOps fondamentaux.

---

## VS Code et WSL2

VS Code reste une application Windows. Les projets Linux sont ouverts via l'intégration WSL :

```text
VS Code Windows
      ↓
WSL
      ↓
Ubuntu
      ↓
projet sous /home/<user>/...
      ↓
outils Linux du projet
```

Le terminal intégré et les extensions liées au projet utilisent ainsi le même environnement Linux que les commandes exécutées dans WezTerm `Ubuntu DevOps (WSL2)`.

Le poste prend en charge les extensions nécessaires aux usages DevOps, Kubernetes, Terraform, YAML, GitHub Actions et aux connexions distantes prévues par le projet.

Les secrets et paramètres personnels de connexion restent hors du dépôt.

---

## Répertoires de travail préparés

Le bootstrap Linux peut préparer :

```text
~/projects
~/labs
~/repositories
~/scripts
~/workspace
~/backups
```

Ils restent dans le filesystem Linux.

---

## Validation

Validation DevOps :

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

Elle peut couvrir :

- présence et versions des outils attendus ;
- service Docker et plugins ;
- HOME Linux ;
- racines de travail ;
- profil shell ;
- qualité Bash ;
- actionlint ;
- smoke tests IaC.

Validation du terminal WezTerm :

```powershell
.\install.ps1 -Mode Verify
```

Validation OpenClaw lorsqu'il est utilisé :

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

Ces validations sont complémentaires : **terminal conforme**, **stack Linux conforme** et **runtime OpenClaw conforme** sont trois faits distincts.

Voir [`11_VALIDATION.md`](11_VALIDATION.md).

---

## Règle à retenir

```text
Windows = hôte et outils Windows-native
Ubuntu  = backend et projets Linux DevOps
WezTerm = routeur terminal entre les contextes
VS Code = UI Windows reliée aux projets WSL2
OpenClaw = runtime IA Windows-native optionnel
```

L'ergonomie reste unifiée ; les responsabilités techniques restent séparées.