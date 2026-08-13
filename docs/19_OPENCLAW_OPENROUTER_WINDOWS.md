# OpenClaw/OpenRouter — intégration Windows et CLI

Ce guide décrit **l'intégration d'OpenClaw/OpenRouter dans la workstation `Windows_11_Pro_Custom`**.

Son périmètre est volontairement limité à ce que possède ce dépôt :

- emplacement local ;
- bootstrap Windows ;
- pin du control-plane ;
- frontière avec WSL2 ;
- accès CLI ;
- profil WezTerm ;
- validation d'intégration ;
- protection des données locales.

La configuration métier d'OpenClaw, les modèles, agents et opérations propres à l'équipe IA restent sous la responsabilité du dépôt `mathiasseguincadiche/openclaw_openrouter`.

OpenClaw est une **extension optionnelle** de la workstation, pas son identité principale.

---

## Place dans l'architecture

```text
Windows 11 Pro
│
├── WezTerm
│   ├── Ubuntu DevOps (WSL2)
│   ├── PowerShell 7
│   └── OpenClaw / clawops (Windows)
│
├── D:\AI\OpenClaw
│   ├── control-plane
│   ├── npm-global
│   ├── state
│   ├── workspace
│   ├── clawops
│   ├── venv
│   ├── logs
│   └── cache
│
└── WSL2
    └── Ubuntu 26.04
        └── backend Linux DevOps
```

La frontière est :

```text
Windows natif -> OpenClaw / OpenRouter / clawops
Ubuntu WSL2   -> Docker / Kubernetes / Terraform / Ansible / AWS / projets Linux
```

WezTerm unifie l'accès utilisateur sans fusionner ces runtimes.

Référence d'architecture : [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md).

---

## Frontière avec les projets Linux

Les checkouts Linux actifs continuent de vivre sous :

```text
~/projects
~/labs
~/repositories
```

Ils ne sont pas déplacés vers `/mnt/c` ou `/mnt/d` pour faciliter l'accès depuis Windows.

Une analyse ou une ingestion effectuée par `clawops` ne remplace pas le checkout opérationnel dans WSL2.

---

## Source de vérité OpenClaw côté workstation

Le dépôt Windows référence le control-plane approuvé dans :

```text
config/openclaw/control-plane.json
```

Ce fichier indique **quel control-plane la workstation doit consommer**.

Le contrat runtime détaillé d'OpenClaw, de Node.js et de `clawops` reste défini dans `openclaw_openrouter`. `Windows_11_Pro_Custom` ne doit pas recopier ces versions ou politiques dans WezTerm ou dans sa documentation générale.

La règle est donc :

```text
config/openclaw/control-plane.json
        ↓
control-plane approuvé
        ↓
contrats runtime possédés par openclaw_openrouter
```

---

## Audit et installation

Audit général :

```powershell
.\install.ps1 -Mode Audit
```

Installation explicite d'OpenClaw :

```powershell
.\install.ps1 -Mode Apply -InstallOpenClawAI
```

Si la stack DevOps doit également converger :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps -InstallOpenClawAI
```

Le raccourci :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

inclut actuellement l'installation et la validation OpenClaw avec les autres qualifications du périmètre complet.

Le parcours Windows vérifie notamment :

1. la présence du stockage attendu ;
2. l'environnement WSL2 nécessaire au backend DevOps ;
3. le chemin `D:\AI\OpenClaw` ;
4. le checkout du control-plane approuvé ;
5. les launchers Windows ;
6. l'environnement utilisateur nécessaire à la CLI ;
7. la séparation avec les workspaces Linux.

Les secrets restent hors de Git.

---

## Variables et emplacements locaux

L'intégration utilise notamment :

```text
OPENCLAW_HOME=D:\AI\OpenClaw
OPENCLAW_STATE_DIR=D:\AI\OpenClaw\state
OPENCLAW_CONFIG_PATH=D:\AI\OpenClaw\state\openclaw.json
OPENCLAW_WORKSPACE_DIR=D:\AI\OpenClaw\workspace
CLAWOPS_HOME=D:\AI\OpenClaw\clawops
CLAWOPS_DEPLOYMENT_MODE=windows-native
CLAWOPS_WSL_DISTRIBUTION=Ubuntu
```

Les launchers sont fournis depuis les emplacements gérés sous `D:\AI\OpenClaw`, notamment :

```text
D:\AI\OpenClaw\npm-global
D:\AI\OpenClaw\venv\Scripts
```

Ces chemins appartiennent au runtime IA Windows. Ils ne deviennent pas des répertoires de travail Linux.

---

# CLI OpenClaw via WezTerm

La configuration `config/wezterm/wezterm.lua` expose :

```text
Ubuntu DevOps (WSL2)
PowerShell 7
OpenClaw / clawops (Windows)
```

Le profil **`OpenClaw / clawops (Windows)`** ouvre PowerShell 7 sur l'hôte Windows.

## Ce que prépare le profil

La préparation est limitée à la session terminal ouverte :

1. relire les variables utilisateur OpenClaw pertinentes ;
2. compléter le `PATH` de session avec les répertoires CLI gérés lorsqu'ils existent ;
3. privilégier les launchers Windows `openclaw.cmd` et `clawops.exe` ;
4. se positionner sous `D:\AI\OpenClaw` lorsque la racine existe ;
5. vérifier si `openclaw` et `clawops` sont disponibles ;
6. laisser PowerShell interactif à l'utilisateur.

Cette préparation n'écrit pas un second contrat OpenClaw et ne remplace pas le bootstrap.

## Ce que le profil ne possède pas

WezTerm n'est pas un orchestrateur IA. Le profil ne possède pas :

- l'installation du runtime ;
- les versions OpenClaw/Node.js ;
- les modèles ;
- les agents ;
- les politiques de budget ;
- les opérations fonctionnelles du control-plane.

Ces responsabilités restent dans `openclaw_openrouter`.

## Smoke test CLI

Après validation de l'intégration :

```powershell
openclaw --version
clawops version
clawops platform check
```

Ce test prouve que l'utilisateur peut atteindre les deux CLI depuis le terminal prévu. Il ne remplace pas la validation structurée du projet.

Aucune relance de WezTerm n'est nécessaire uniquement pour rafraîchir les variables ou les chemins gérés par ce profil : la session OpenClaw relit elle-même l'environnement utilisateur pertinent.

---

## OpenRouter dans ce dépôt

OpenRouter est un service externe consommé par OpenClaw. Le dépôt Windows ne possède ni le fournisseur, ni la configuration métier des modèles.

Sa responsabilité se limite à fournir une workstation locale capable d'héberger le runtime OpenClaw conformément au control-plane approuvé.

Les informations d'authentification OpenRouter restent hors du dépôt.

---

## Validation

Validation de l'intégration OpenClaw :

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

Qualification combinée lorsque la workstation complète est utilisée :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateOpenClawAI
```

Les preuves sont séparées :

```text
install.ps1 -Mode Verify
        ↓
configuration workstation et WezTerm conformes

-ValidateOpenClawAI
        ↓
runtime OpenClaw / control-plane / intégration conformes

-ValidateWsl + -ValidateDevOps
        ↓
backend Linux DevOps conforme
```

Le fait que le profil WezTerm existe ne prouve donc pas à lui seul qu'OpenClaw est installé.

---

## Données locales et sauvegarde

`D:\AI\OpenClaw` peut contenir du state, des sessions, des caches et des données de travail.

La stratégie de sauvegarde de la workstation doit donc prendre en compte :

- les données de `D:` ;
- l'état OpenClaw utile ;
- Ubuntu WSL2 selon la politique du projet ;
- le dépôt Git comme source du socle versionné.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

## Relation entre les deux dépôts

```text
Windows_11_Pro_Custom
        ↓
prépare et valide la workstation
        ↓
Windows + WSL2 + WezTerm + D:\AI\OpenClaw
        ↓
openclaw_openrouter
        ↓
runtime et fonctions IA
```

Cette séparation évite que le dépôt Windows devienne une seconde documentation fonctionnelle d'OpenClaw.

---

## Critère de sortie

L'intégration locale est prête lorsque :

```text
workstation Windows conforme
+
configuration WezTerm conforme
+
profil OpenClaw / clawops accessible
+
control-plane approuvé
+
OpenClaw Windows validé
+
WSL2 DevOps conforme lorsque requis
+
frontières de stockage respectées
+
secrets hors de Git
```

La checklist globale du projet est [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md).