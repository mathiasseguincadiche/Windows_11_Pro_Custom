# Orchestration, logs et idempotence V9

## Objectif

V9 transforme `install.ps1` en orchestrateur fiable. Le principe est simple : **observer avant de décider, vérifier avant d'écrire, re-vérifier après chaque changement**.

Aucun fichier `state/` ne suffit à prouver que la machine est conforme. Ces fichiers servent au rollback. La conformité vient de faits relus sur la machine au moment de l'exécution.

## Cycle d'une exécution

```text
PowerShell administrateur
        ↓
Discovery / état réel
        ↓
Verify de chaque composant
        ↓
PLAN FACTUEL
├── DÉJÀ OK
├── À FAIRE
├── ACTION REQUISE
└── IGNORE
        ↓
confirmation avant mutation
        ↓
Apply uniquement des écarts
        ↓
re-Verify de chaque composant modifié
        ↓
validations globales
        ↓
summary.json + logs par script
```

## Cas gérés

### Première installation

V9 détecte l'absence des composants et affiche ce qui va être installé. Aucun composant absent n'est présenté comme fonctionnel.

### Installation partielle

Les composants déjà conformes sont marqués `DÉJÀ OK` et ignorés. Seuls les écarts passent par Apply.

### Relance après installation complète

Les Verify réussissent, le plan indique que l'installation demandée est déjà conforme, et aucun réglage/application/point de restauration n'est recréé inutilement.

### Exécution interrompue

Il suffit de relancer la même commande. L'état est recalculé depuis la machine ; les étapes terminées sont ignorées et la reprise porte sur les éléments restants.

## Commandes principales

### Lire la machine sans modifier

```powershell
.\install.ps1 -Mode Audit
```

### Voir seulement le plan d'installation

```powershell
.\install.ps1 -Mode Apply -PlanOnly
```

`PlanOnly` exécute la découverte et les Verify, puis s'arrête avant toute mutation.

### Installation standard interactive

```powershell
.\install.ps1 -Mode Apply
```

Avant les changements, l'orchestrateur demande :

```text
Continuer ? [O/N]
```

### Installation DevOps

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

Si Ubuntu vient d'être installée sans utilisateur Linux normal, V9 demande un nom d'utilisateur puis Linux demande directement le mot de passe via `adduser`. Le mot de passe est masqué par Linux et n'est pas transmis comme variable PowerShell.

### Installation complète

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

`FullInstall` inclut la stack DevOps, OpenClaw/OpenRouter et les qualifications finales demandées. Les preuves physiques V5 restent humaines : V9 ne peut pas inventer un réglage BIOS ou la position d'un SSD.

### Automatisation non interactive

```powershell
.\install.ps1 -Mode Apply -NonInteractive -Yes -WslUser mathias
```

`-Yes` est obligatoire en mode non interactif pour autoriser les mutations. Si une étape exige une saisie sécurisée impossible en non interactif (par exemple la création d'un nouvel utilisateur Linux avec mot de passe), l'exécution s'arrête avec l'action exacte à effectuer ; elle ne contourne pas la sécurité.

### Vérification complète

```powershell
.\install.ps1 -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateOpenClawAI
```

## Utilisateur WSL

Le script `scripts/bootstrap/07_wsl_user.ps1` vérifie :

1. l'utilisateur Linux existe réellement dans `/etc/passwd` ;
2. il n'est pas `root` ;
3. il appartient au groupe `sudo` ;
4. `/etc/wsl.conf` le définit comme utilisateur par défaut ;
5. après redémarrage logique de la distribution, `id -un` retourne réellement cet utilisateur.

Saisie guidée directe :

```powershell
.\scripts\bootstrap\07_wsl_user.ps1 -Mode Apply -Distribution Ubuntu
```

## Preuves matérielles manuelles

Les informations impossibles à mesurer de façon fiable par Windows restent explicitement marquées `ACTION REQUISE`.

Saisie guidée :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Record -Interactive
```

Le script pose une question précise pour chaque preuve encore manquante et conserve les confirmations déjà enregistrées.

## Logs

Voir `logs/README.md`.

Chaque script exécuté par l'orchestrateur possède un log persistant distinct, par exemple :

```text
logs/bootstrap/03_apps.log
logs/windows/10_tune.log
logs/windows/53_responsiveness_v8.log
logs/wsl/install-devops.log
logs/wsl/validate-devops.log
```

Chaque run possède également :

```text
logs/runs/<run-id>/events.ndjson
logs/runs/<run-id>/summary.json
```

## Rapports factuels

```text
reports/orchestration/machine-state.json
reports/orchestration/latest-run.json
```

`machine-state.json` est régénéré à chaque exécution normale. Il décrit notamment Windows, CPU/RAM, C:/D:, WinGet, applications automatiques, WSL, VS Code, WezTerm, OpenSSH, OneDrive, Defender et les redémarrages en attente.

## Règles d'idempotence

- WinGet : `winget list --id ... --exact` avant toute installation, puis relecture après installation.
- Registre Windows : comparaison valeur/type avant écriture.
- Services V4 : comparaison du mode de démarrage avant `Set-Service`.
- VS Code : hash `settings.json` et liste réelle d'extensions.
- WezTerm : présence de l'application et hash du fichier de configuration.
- OpenSSH : état de la capability Windows + présence de `ssh.exe`.
- OneDrive : processus, exécutables, WinGet et politiques registre.
- WSL : distribution, version WSL2, `.wslconfig`, emplacement observé, release Ubuntu.
- DevOps : validation Linux dédiée avant de lancer le bootstrap.
- Réactivité V8 : Verify avant Apply via l'orchestrateur.

## Ce que V9 refuse

- considérer un ancien fichier d'état comme preuve de conformité actuelle ;
- déclarer une installation réussie sans revalidation ;
- réinstaller un composant déjà conforme ;
- enregistrer volontairement un mot de passe dans les logs ;
- inventer une donnée BIOS, physique ou matérielle non mesurable ;
- continuer silencieusement lorsqu'une entrée utilisateur est nécessaire.
