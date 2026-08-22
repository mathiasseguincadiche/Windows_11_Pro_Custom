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

`/mnt/c` et `/mnt/e` restent accessibles pour des échanges ponctuels avec Windows, mais sont **interdits comme racines de projets ou de workspaces DevOps**.

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
- AWS CLI, version 2 ;
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

# Windows Terminal — point d'entrée moderne de la workstation

Windows Terminal ne constitue pas un troisième runtime. Il sert de **routeur explicite vers les environnements possédés par la workstation** et constitue l'application terminal système attendue sous Windows.

Les configurations de référence sont :

```text
config/windows-terminal/profiles.fragment.json
config/windows-terminal/actions.json
config/windows-terminal/settings.contract.json
config/windows-terminal/starship.windows.toml
```

Le contrat moderne expose exactement trois profils gérés :

```text
Windows Terminal
├── PowerShell 7 - DevOps         <- défaut, session Windows normale
├── PowerShell 7 - DevOps (Admin) <- profil élevé via UAC
└── Ubuntu - DevOps               <- WSL2, démarre dans ~
```

Les profils dynamiques PowerShell Core et WSL générés automatiquement par Windows Terminal sont désactivés afin d'éviter les doublons avec ces profils explicitement versionnés.

## Windows Terminal comme application terminal par défaut

La convergence configure Windows Terminal Stable comme application terminal système via le mécanisme de délégation Windows prévu à cet effet sous :

```text
HKCU\Console\%%Startup
```

Les valeurs `DelegationConsole` et `DelegationTerminal` sont observées, sauvegardées avant la première mutation, appliquées puis vérifiées. `Rollback` restaure les valeurs qui existaient avant la prise en charge par le dépôt.

Cette couche est distincte du simple `defaultProfile` de Windows Terminal :

- **application terminal par défaut** = Windows choisit Windows Terminal comme hôte moderne ;
- **profil Windows Terminal par défaut** = Windows Terminal ouvre `PowerShell 7 - DevOps` lorsqu'aucun profil n'est demandé explicitement.

Le composant exige une version Windows Terminal compatible avec le contrat moderne avant application.

## Profil `PowerShell 7 - DevOps`

C'est le profil Windows Terminal par défaut.

Il ouvre PowerShell 7 sur l'hôte Windows et sert notamment à :

- `install.ps1` ;
- `update.ps1` ;
- les commandes Windows-native ;
- les opérations courantes ne nécessitant pas d'élévation ;
- les accès ponctuels à WSL via les helpers du profil PowerShell.

Le profil démarre dans `%USERPROFILE%`, utilise JetBrainsMono Nerd Font, le schéma `WPC DevOps`, un titre d'onglet stable et n'autorise pas les applications console à réécrire automatiquement ce titre.

## Profil `PowerShell 7 - DevOps (Admin)`

Ce profil représente explicitement la session Windows privilégiée.

Il utilise :

```text
elevate = true
```

Windows Terminal déclenche donc l'élévation UAC pour ce profil. Son titre, son onglet et son schéma `WPC DevOps Admin` sont visuellement distincts du profil normal afin de réduire le risque de confusion entre une console standard et une console administrateur.

Le profil PowerShell géré détecte également le jeton administrateur et expose `WPC_ELEVATED=Admin` à Starship, qui peut afficher cet état dans le prompt.

## Profil `Ubuntu - DevOps`

Ce profil exécute :

```text
wsl.exe -d Ubuntu
```

et définit explicitement :

```text
startingDirectory = ~
```

Il doit être utilisé pour :

- les projets sous `~/projects`, `~/labs`, `~/repositories` ;
- Docker et Kubernetes ;
- Terraform et Ansible ;
- AWS CLI et GitHub CLI côté Linux ;
- les scripts Bash et outils qualité Linux.

Il matérialise la règle : **les workloads Linux restent dans Linux**.

Le profil Windows Terminal ne configure pas lui-même Bash. Il ouvre la distribution, puis le shell géré par `scripts/wsl/manage-devops-terminal.sh` et `scripts/wsl/manage-shell-profile.sh` prend le relais.

## Onglets et raccourcis gérés

```text
Ctrl+T         -> nouvel onglet PowerShell 7 - DevOps
Ctrl+Shift+1   -> PowerShell 7 - DevOps
Ctrl+Shift+2   -> Ubuntu - DevOps
Ctrl+Shift+3   -> PowerShell 7 - DevOps (Admin)
Ctrl+Shift+R   -> renommer l'onglet courant
Ctrl+W         -> fermer l'onglet courant
Ctrl+Shift+O   -> PowerShell + Ubuntu en panneaux
```

Le renommage utilise l'action native `openTabRenamer`. Comme les profils gérés utilisent `suppressApplicationTitle`, un nom d'onglet choisi manuellement n'est pas immédiatement remplacé par le titre émis par `pwsh`, WSL ou une application console.

Le menu `+` regroupe les trois profils dans un dossier `Windows 11 Pro Custom`, expose le workspace PowerShell + Ubuntu et conserve les autres profils utilisateur via `remainingProfiles`.

## Apparence Windows 11 moderne

Le contrat `settings.contract.json` possède uniquement les réglages nécessaires à l'expérience gérée et préserve les réglages utilisateur non possédés.

Il définit notamment :

- thème sombre `WPC DevOps` ;
- Mica pour la fenêtre ;
- lancement maximisé ;
- réutilisation de la fenêtre active pour les onglets standards ;
- onglets toujours visibles ;
- largeur d'onglet basée sur le titre ;
- schémas distincts normal / Admin / Ubuntu ;
- avertissement pour les collages multilignes ou volumineux ;
- copie au simple survol/sélection désactivée ;
- mise en forme du presse-papiers désactivée.

Les profils utilisent un fond sombre, une opacité légère, un padding uniforme, une barre de défilement masquée et JetBrainsMono Nerd Font. Aucun fond décoratif ni effet rétro n'est imposé.

## PowerShell, Starship, UTF-8 et PSReadLine

Starship est initialisé depuis :

```text
~/.config/windows11-pro-custom/starship.windows.toml
```

Le bloc PowerShell géré configure également :

- entrée et sortie console UTF-8 ;
- rendu ANSI PowerShell 7 ;
- PSReadLine en mode Windows ;
- prédictions basées sur l'historique ;
- affichage des prédictions en `ListView` ;
- historique sans doublons ;
- complétion de type menu avec `Tab` ;
- bip console désactivé ;
- détection de l'état administrateur pour le prompt.

Le dépôt ne remplace pas l'intégralité du profil PowerShell utilisateur : il possède uniquement un bloc borné et idempotent.

---

## Contrat Windows Terminal et convergence

Le point d'entrée reste :

```text
scripts/windows/31_windows_terminal.ps1
```

Il délègue au moteur moderne `31_windows_terminal_modern.ps1` afin de conserver la compatibilité avec l'orchestrateur tout en isolant la logique de convergence.

Les quatre modes restent :

```text
Audit    -> observer sans modifier
Apply    -> sauvegarder l'état initial puis converger uniquement les écarts
Verify   -> prouver le contrat attendu
Rollback -> restaurer les fichiers et la délégation terminal initialement observés
```

Le composant vérifie notamment :

- Windows Terminal et sa version minimale ;
- Windows Terminal comme application terminal par défaut ;
- PowerShell 7 ;
- Starship Windows ;
- JetBrainsMono Nerd Font ;
- la distribution WSL `Ubuntu` ;
- les trois profils gérés ;
- le profil PowerShell par défaut ;
- le profil Admin avec `elevate=true` ;
- Ubuntu démarrant dans `~` ;
- les sept raccourcis gérés ;
- le thème Mica et les trois schémas de couleurs ;
- le menu `+` ;
- le bloc PowerShell géré ;
- la conservation des réglages utilisateur non possédés ;
- l'idempotence de la transformation de `settings.json`.

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

Application ou réparation de Windows Terminal :

```powershell
.\scripts\windows\31_windows_terminal.ps1 -Mode Apply
```

Validation de Windows Terminal :

```powershell
.\scripts\windows\31_windows_terminal.ps1 -Mode Verify
```

Rollback de la seule intégration terminal :

```powershell
.\scripts\windows\31_windows_terminal.ps1 -Mode Rollback
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
Windows Terminal = hôte terminal système + routeur PowerShell 7 / Admin / Ubuntu
VS Code          = UI Windows reliée aux projets WSL2
```

L'ergonomie de la workstation reste cohérente ; les projets externes restent autonomes.
