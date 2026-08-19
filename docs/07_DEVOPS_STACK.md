# Stack DevOps et expérience terminal

Ce guide décrit **la chaîne Linux DevOps et la manière d'y accéder au quotidien depuis Windows**.

OpenClaw/OpenRouter est un projet externe indépendant. Ce dépôt ne documente ni son installation ni sa configuration ; la frontière est fixée dans [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

## Frontière d'exécution

```text
Windows 11 Pro
├── Windows Terminal
├── PowerShell 7
└── VS Code Windows

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

`/mnt/c` et `/mnt/e` servent aux échanges avec Windows, pas de racines quotidiennes aux projets Linux.

Docker Desktop n'est pas requis : Docker Engine tourne directement dans Ubuntu.

L'utilisateur Ubuntu est volontairement autorisé à utiliser Docker Engine sans
`sudo` via le groupe `docker`. Cette appartenance doit être traitée comme un
privilège de niveau root dans la distribution WSL : un compte membre du groupe
`docker` est donc un principal privilégié de la workstation.

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

# Windows Terminal — point d'entrée terminal de la workstation

Windows Terminal ne constitue pas un troisième runtime. Il sert de **routeur explicite vers les environnements possédés par la workstation**.

Les configurations de référence sont :

```text
config/windows-terminal/profiles.fragment.json
config/windows-terminal/actions.json
config/windows-terminal/starship.windows.toml
```

Le contrat courant expose exactement deux profils gérés :

```text
Windows Terminal
├── PowerShell 7 - DevOps <- défaut
└── Ubuntu - DevOps       <- WSL2
```

## Profil `PowerShell 7 - DevOps`

C'est le profil Windows Terminal par défaut.

Il ouvre PowerShell 7 sur l'hôte Windows et sert notamment à :

- `install.ps1` ;
- `update.ps1` ;
- l'administration Windows ;
- les commandes et outils réellement Windows-native ;
- les accès ponctuels à WSL via les helpers du profil PowerShell.

Starship est initialisé depuis :

```text
~/.config/windows11-pro-custom/starship.windows.toml
```

Le dépôt ne remplace pas l'intégralité du profil PowerShell utilisateur : il possède uniquement un bloc borné et idempotent.

## Profil `Ubuntu - DevOps`

Ce profil exécute :

```text
wsl.exe -d Ubuntu
```

Il doit être utilisé pour :

- les projets sous `~/projects`, `~/labs`, `~/repositories` ;
- Docker et Kubernetes ;
- Terraform et Ansible ;
- AWS CLI et GitHub CLI côté Linux ;
- les scripts Bash et outils qualité Linux.

Il matérialise la règle : **les workloads Linux restent dans Linux**.

Le profil Windows Terminal ne configure pas lui-même Bash. Il ouvre la distribution, puis le shell géré par `scripts/wsl/manage-devops-terminal.sh` et `scripts/wsl/manage-shell-profile.sh` prend le relais.

## Raccourcis gérés

```text
Ctrl+Shift+1 -> PowerShell 7 - DevOps
Ctrl+Shift+2 -> Ubuntu - DevOps
Ctrl+Shift+O -> PowerShell + Ubuntu en panneaux
```

Les profils dynamiques PowerShell Core et WSL générés automatiquement par Windows Terminal sont désactivés dans le contrat géré afin d'éviter les doublons avec les deux profils explicitement versionnés.

---

## Contrat Windows Terminal et convergence

`scripts/windows/31_windows_terminal.ps1` fonctionne comme les autres composants workstation :

```text
Audit    -> observer sans modifier
Apply    -> sauvegarder l'état initial puis converger uniquement les écarts
Verify   -> prouver le contrat attendu
Rollback -> restaurer uniquement les fichiers possédés dont l'état initial a été enregistré
```

Le composant vérifie notamment :

- Windows Terminal ;
- PowerShell 7 ;
- Starship Windows ;
- JetBrainsMono Nerd Font ;
- la distribution WSL `Ubuntu` ;
- les deux profils gérés ;
- le profil par défaut ;
- les raccourcis importés ;
- le bloc PowerShell géré.

Il **n'installe aucune de ces dépendances lui-même** : Windows Terminal, PowerShell 7, Starship et la Nerd Font appartiennent au manifeste WinGet, tandis que WSL appartient au bootstrap WSL2.

Le validateur refuse également qu'une intégration spécifique à OpenClaw/`clawops` soit ajoutée à cette expérience terminal de la workstation : une telle intégration, si elle est souhaitée, appartient au dépôt `openclaw_openrouter`.

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

Le terminal intégré et les extensions liées au projet utilisent ainsi le même environnement Linux que les commandes exécutées depuis Windows Terminal avec `Ubuntu - DevOps`.

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

Validation de Windows Terminal :

```powershell
.\scripts\windows\31_windows_terminal.ps1 -Mode Verify
```

ou dans la validation globale :

```powershell
.\install.ps1 -Mode Verify
```

OpenClaw/OpenRouter possède sa propre installation, sa propre configuration et sa propre validation dans `mathiasseguincadiche/openclaw_openrouter`. Aucune commande `ValidateOpenClawAI` n'appartient à ce dépôt.

Voir [`11_VALIDATION.md`](11_VALIDATION.md).

---

## Règle à retenir

```text
Windows          = hôte et outils Windows-native de la workstation
Ubuntu           = backend et projets Linux DevOps
Windows Terminal = routeur terminal PowerShell 7 / Ubuntu
VS Code          = UI Windows reliée aux projets WSL2
```

L'ergonomie de la workstation reste cohérente ; les projets externes restent autonomes.
