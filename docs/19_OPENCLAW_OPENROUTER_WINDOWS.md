# OpenClaw + OpenRouter sous Windows 11 — installation propre sur D:\

Cette intégration ajoute la pile IA du dépôt privé `mathiasseguincadiche/openclaw_openrouter` au poste `Windows_11_Pro_Custom` avec une séparation stricte entre le runtime Windows et le backend Linux DevOps.

## Architecture retenue

```text
C:\
└── Windows 11 Pro + applications système

D:\WSL\Ubuntu-DevOps\
└── Ubuntu 26.04 WSL2
    ├── Git / Bash / systemd
    ├── Docker Engine
    ├── Terraform / Ansible / AWS CLI
    └── kubectl / Helm / Minikube / kind

D:\AI\OpenClaw\
├── control-plane\     # checkout détaché du commit OpenClaw approuvé
├── npm-global\        # runtime npm OpenClaw épinglé par le control-plane
├── state\             # configuration, credentials, sessions et état OpenClaw
├── workspace\         # workspace principal
├── clawops\           # projets, intake et état du toolkit
├── venv\              # Python + CLI clawops
├── logs\
└── cache\
```

La séparation est volontaire :

```text
Windows natif
└── OpenClaw + OpenRouter + clawops

WSL2 Ubuntu 26.04
└── exécution des charges DevOps Linux
```

Un dépôt Linux actif reste sous le filesystem Linux, par exemple :

```text
~/projects
~/labs
~/repositories
```

Il ne doit pas être déplacé sous `/mnt/c` ou `/mnt/d` pour faciliter l'accès depuis Windows. Une ingestion `clawops project ingest` est une copie d'analyse/audit et ne remplace jamais le checkout opérationnel WSL2.

## Pin immuable du control-plane

Le dépôt Windows ne suit pas une branche mobile de `openclaw_openrouter`. La source de vérité est :

```text
config/openclaw/control-plane.json
```

Le champ `ref` contient un SHA Git de 40 caractères validé par CI. Le bootstrap :

1. récupère exactement ce ref ;
2. utilise un checkout détaché ;
3. vérifie que `HEAD` correspond au SHA attendu ;
4. refuse d'écraser un checkout contenant des modifications locales.

Une montée de version OpenClaw se fait donc volontairement dans le dépôt IA, avec tests, puis par mise à jour explicite du pin dans ce dépôt.

## Audit

Depuis PowerShell 7 :

```powershell
.\install.ps1 -Mode Audit
```

L'audit contrôle notamment :

- `D:` en NTFS ;
- la présence éventuelle de `D:\AI\OpenClaw\control-plane` ;
- le commit control-plane attendu et le `HEAD` local ;
- les launchers OpenClaw et `clawops` ;
- la présence du validateur WSL2 fourni par le control-plane ;
- les variables utilisateur persistées.

## Installation

```powershell
.\install.ps1 -Mode Apply -InstallDevOps -InstallOpenClawAI
```

Le bootstrap Windows :

1. prépare WSL2 Ubuntu selon le contrat `config/wsl/runtime-contract.json` ;
2. installe la stack DevOps dans Ubuntu si `-InstallDevOps` est demandé ;
3. vérifie que la cible IA est `D:` en NTFS ;
4. installe Git for Windows si nécessaire ;
5. clone le dépôt privé OpenClaw sous `D:\AI\OpenClaw\control-plane` ;
6. positionne le checkout sur le commit immuable approuvé ;
7. lance l'installateur Windows versionné du control-plane ;
8. conserve tous les secrets hors de Git.

Le dépôt IA étant privé, Git Credential Manager doit être authentifié auprès de GitHub lors du premier clone.

## Runtime OpenClaw et Node.js

Le control-plane contient son propre contrat runtime machine-readable. Il fixe notamment :

- la version OpenClaw validée ;
- les plages Node.js supportées ;
- la distribution WSL2 DevOps ;
- les racines Linux autorisées et interdites.

L'installateur ne dépend donc plus de `openclaw@latest`. Il refuse une version OpenClaw différente du lock et vérifie la version réelle de Node.js avant installation ou validation.

## Variables persistées

```text
OPENCLAW_HOME=D:\AI\OpenClaw
OPENCLAW_STATE_DIR=D:\AI\OpenClaw\state
OPENCLAW_CONFIG_PATH=D:\AI\OpenClaw\state\openclaw.json
OPENCLAW_WORKSPACE_DIR=D:\AI\OpenClaw\workspace
CLAWOPS_HOME=D:\AI\OpenClaw\clawops
CLAWOPS_DEPLOYMENT_MODE=windows-native
CLAWOPS_WSL_DISTRIBUTION=Ubuntu
```

## OpenRouter

La clé API n'est pas demandée automatiquement pendant l'installation par défaut.

Quand vous êtes prêt :

```powershell
openclaw onboard --auth-choice openrouter-api-key
```

Puis :

```powershell
clawops validate config
clawops validate models
clawops budget status
clawops team deploy
clawops team status
```

## Gateway

Le Gateway reste une décision explicite :

```powershell
openclaw gateway install
openclaw gateway status --json
```

L'exposition réseau ne doit pas être élargie sans besoin explicite. La qualification du socle Windows/WSL2 ne force pas l'installation ou la publication du Gateway.

## Qualification complète

Après installation de la stack DevOps et d'OpenClaw :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateOpenClawAI
```

Cette séquence vérifie :

```text
Windows 11 / D: NTFS
        ↓
control-plane OpenClaw au SHA épinglé
        ↓
OpenClaw Windows + Node.js + clawops
        ↓
Ubuntu 26.04 WSL2
        ↓
HOME et workspaces Linux sur ext4
        ↓
Git / Docker / Terraform / Ansible / AWS / kubectl / Helm
        ↓
frontière /mnt/c et /mnt/d respectée
```

Verdicts attendus incluent notamment :

```text
VERDICT: V6 WSL2 PLATFORM READY
VERDICT: V3 DEVOPS READY
VERDICT: OPENCLAW WINDOWS D DRIVE READY
VERDICT: OPENCLAW WSL DEVOPS BACKEND READY
VERDICT: OPENCLAW AI READY
```

Le dernier verdict `OPENCLAW AI READY` n'est émis qu'après validation du runtime Windows et du backend DevOps WSL2 fourni par le control-plane épinglé.

## Rollback

`install.ps1 -Mode Rollback` ne supprime jamais automatiquement `D:\AI\OpenClaw` ni la distribution WSL2.

C'est volontaire : `state` peut contenir des credentials, des sessions et des données de travail. Toute suppression, migration ou restauration destructive reste une décision explicite précédée d'une sauvegarde.

## Sauvegarde

La stratégie V7 protège `C:` et `D:` et exporte séparément la distribution WSL2 en VHDX avec SHA-256. `D:\AI\OpenClaw` est donc inclus dans la protection du volume DATA tandis que l'environnement Linux dispose de son export dédié.

Les sauvegardes contenant `D:\AI\OpenClaw\state` doivent être traitées comme sensibles et conservées sur un support de confiance.
