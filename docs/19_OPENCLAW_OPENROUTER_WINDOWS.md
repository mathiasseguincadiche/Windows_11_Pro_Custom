# OpenClaw + OpenRouter sous Windows 11 — intégration sur `D:`

Cette documentation explique **la place d'OpenClaw/OpenRouter dans la workstation Windows**.

Elle ne remplace pas la documentation fonctionnelle du dépôt `mathiasseguincadiche/openclaw_openrouter`. Le dépôt Windows prépare l'environnement, les emplacements, les frontières avec WSL2 et la validation d'intégration.

OpenClaw est une **capacité optionnelle** de la workstation, pas son identité principale.

---

## Architecture

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
├── control-plane\
├── npm-global\
├── state\
├── workspace\
├── clawops\
├── venv\
├── logs\
└── cache\
```

La séparation est volontaire :

```text
Windows natif
└── OpenClaw / OpenRouter / clawops

Ubuntu WSL2
└── backend Linux DevOps
```

---

## Frontière avec les projets Linux

Un dépôt Linux actif continue de vivre sous :

```text
~/projects
~/labs
~/repositories
```

Il ne doit pas être déplacé vers `/mnt/c` ou `/mnt/d` pour faciliter l'accès depuis Windows.

Une ingestion par `clawops` sert à l'analyse ou à l'audit ; elle ne remplace pas le checkout opérationnel WSL2.

---

## Control-plane épinglé

Le dépôt Windows ne suit pas aveuglément une branche mobile de `openclaw_openrouter`.

La source de vérité est :

```text
config/openclaw/control-plane.json
```

Le bootstrap :

1. récupère le ref approuvé ;
2. vérifie le checkout ;
3. refuse d'écraser des modifications locales non prévues ;
4. utilise le contrôle-plane validé pour installer et qualifier la pile.

Une mise à jour OpenClaw doit donc être testée dans le dépôt IA, puis le pin Windows est mis à jour explicitement.

---

## Audit

Depuis PowerShell 7 :

```powershell
.\install.ps1 -Mode Audit
```

L'audit peut contrôler notamment :

- `D:` en NTFS ;
- présence de `D:\AI\OpenClaw` ;
- checkout du control-plane ;
- launchers OpenClaw et `clawops` ;
- environnement WSL2 attendu ;
- variables utilisateur pertinentes ;
- cohérence des frontières Windows/Linux.

---

## Installation

Si la stack DevOps et OpenClaw doivent être installés :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps -InstallOpenClawAI
```

Le parcours Windows :

1. qualifie WSL2 Ubuntu ;
2. installe/converge la stack DevOps si demandée ;
3. vérifie que la cible IA se trouve sur `D:` NTFS ;
4. prépare Git Windows si nécessaire ;
5. récupère le control-plane sous `D:\AI\OpenClaw\control-plane` ;
6. positionne le checkout sur le ref approuvé ;
7. appelle l'installateur Windows du control-plane ;
8. conserve les secrets hors de Git.

Le dépôt IA étant privé, l'authentification GitHub doit être disponible pour le clone initial.

---

## Runtime OpenClaw et Node.js

Le control-plane possède son propre contrat runtime machine-readable.

Il fixe notamment :

- la version OpenClaw validée ;
- les versions Node.js supportées ;
- le mode de déploiement ;
- les frontières WSL2 ;
- les racines autorisées pour les projets Linux.

Le dépôt Windows ne doit pas remplacer ce contrat par un `openclaw@latest` arbitraire.

---

## Variables d'environnement

Architecture attendue :

```text
OPENCLAW_HOME=D:\AI\OpenClaw
OPENCLAW_STATE_DIR=D:\AI\OpenClaw\state
OPENCLAW_CONFIG_PATH=D:\AI\OpenClaw\state\openclaw.json
OPENCLAW_WORKSPACE_DIR=D:\AI\OpenClaw\workspace
CLAWOPS_HOME=D:\AI\OpenClaw\clawops
CLAWOPS_DEPLOYMENT_MODE=windows-native
CLAWOPS_WSL_DISTRIBUTION=Ubuntu
```

Ces chemins séparent clairement l'état IA des projets Linux DevOps.

---

## OpenRouter

OpenRouter est un **service Cloud/API**, pas un logiciel à installer localement.

La workstation prépare OpenClaw ; la configuration de la clé OpenRouter se fait explicitement selon les mécanismes du dépôt IA.

Exemple :

```powershell
openclaw onboard --auth-choice openrouter-api-key
```

Puis les commandes `clawops` du control-plane peuvent être utilisées pour valider la configuration, les modèles, le budget et l'équipe IA.

La clé API ne doit jamais être commitée dans ce dépôt.

---

## Gateway

Le Gateway reste une action explicite :

```powershell
openclaw gateway install
openclaw gateway status --json
```

L'exposition réseau ne doit pas être élargie sans besoin clair.

La qualification de la workstation Windows/WSL2 n'oblige pas à publier automatiquement un Gateway.

---

## Qualification

Après installation :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateOpenClawAI
```

La chaîne de validation doit démontrer :

```text
Windows 11 + D: NTFS
        ↓
control-plane approuvé
        ↓
OpenClaw Windows + Node.js + clawops
        ↓
Ubuntu 26.04 WSL2
        ↓
HOME et projets Linux sur ext4
        ↓
Docker / Terraform / Ansible / AWS / Kubernetes
        ↓
frontière Windows/Linux respectée
```

Les sorties internes de certains validateurs peuvent conserver des identifiants techniques historiques tant que les scripts n'ont pas été refactorés, mais **la documentation utilisateur ne les présente plus comme des versions actives de la workstation**.

---

## Rollback

```powershell
.\install.ps1 -Mode Rollback
```

ne doit jamais supprimer automatiquement :

```text
D:\AI\OpenClaw
Ubuntu WSL2
```

`state` peut contenir des credentials, sessions et données de travail.

Toute suppression, migration ou restauration destructive doit rester une décision explicite précédée d'une sauvegarde.

---

## Sauvegarde

La stratégie de la workstation protège :

- `C:` ;
- `D:` ;
- l'état OpenClaw présent sur `D:` ;
- Ubuntu via un export WSL dédié et vérifié.

Les sauvegardes contenant `D:\AI\OpenClaw\state` sont sensibles.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

## Relation avec le dépôt OpenClaw/OpenRouter

```text
Windows_11_Pro_Custom
        ↓
prépare la workstation
        ↓
Windows + D:\AI + WSL2 backend
        ↓
openclaw_openrouter
        ↓
configuration IA, modèles, agents, clawops, Gateway
```

Le dépôt Windows ne doit pas dupliquer la documentation fonctionnelle de l'équipe IA.

Son rôle est de garantir que la plateforme locale est correctement installée, isolée, validée et sauvegardable.

---

## Règle de sortie

L'intégration est considérée prête lorsque :

```text
workstation Windows conforme
+
WSL2 DevOps conforme
+
control-plane approuvé
+
OpenClaw Windows validé
+
frontières de stockage respectées
+
secrets hors de Git
```

OpenClaw reste alors une **extension propre de la workstation**, sans transformer le projet Windows en simple installateur IA.
