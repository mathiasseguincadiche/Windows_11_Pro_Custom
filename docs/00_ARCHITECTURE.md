# Architecture — Windows 11 Pro Custom

Ce document décrit **où vit chaque composant, qui en est responsable et quelles frontières ne doivent pas être mélangées**.

Pour la vision consolidée du projet : [`18_GUIDE_MAITRE.md`](18_GUIDE_MAITRE.md).

---

## Vue d'ensemble

```text
                         WINDOWS 11 PRO
┌─────────────────────────────────────────────────────────────────┐
│ Interface / applications / drivers / sécurité                  │
│                                                                 │
│  PowerShell 7        VS Code                 WezTerm             │
│       │                 │                       │                │
│       │                 └──── WSL Remote ──────┤                │
│       │                                         │                │
│       ├── install.ps1 / update.ps1              │                │
│       └── menu.ps1                              │                │
│                                                 ▼                │
│                                         Ubuntu WSL2              │
│                                    ┌───────────────────────┐     │
│                                    │ Bash DevOps           │     │
│                                    │ Docker Engine         │     │
│                                    │ kubectl / Helm        │     │
│                                    │ Terraform / Ansible   │     │
│                                    │ AWS / gh / qualité    │     │
│                                    └───────────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

Le projet utilise Windows comme **hôte principal** et WSL2 comme **backend Linux DevOps**.

---

## Architecture physique du stockage

```text
Crucial T705 #1
└── C: NTFS
    ├── Windows 11 Pro
    ├── applications Windows
    ├── drivers
    └── profil utilisateur

Crucial T705 #2
└── D: NTFS
    ├── données
    ├── D:\WSL\Ubuntu-DevOps
    ├── D:\WSL\swap\wsl-swap.vhdx
    ├── D:\AI\OpenClaw
    ├── ISO
    └── exports

Disque USB séparé
└── sauvegarde de référence
```

### Invariant

Il n'existe **aucune partition EXT4 physique** prévue par le projet.

Le filesystem ext4 Ubuntu se trouve dans le VHDX WSL2, lui-même stocké sur `D:` NTFS.

---

## Pourquoi deux SSD ?

### `C:` — système

Responsabilités :

- Windows 11 Pro ;
- applications Windows ;
- drivers ;
- profil utilisateur ;
- composants directement liés à l'OS.

### `D:` — données et environnements lourds

Responsabilités :

- données ;
- WSL2 ;
- OpenClaw ;
- ISO ;
- exports et artefacts volumineux.

Cette séparation limite la pression sur le volume système tout en conservant les deux SSD dans une architecture Windows cohérente et sauvegardable.

---

## Windows reste l'hôte

Windows est responsable de :

```text
matériel / drivers
sécurité Windows
Windows Update
WinGet
PowerShell
applications graphiques
VS Code UI
WezTerm
gaming
runtime WSL
backup Windows
```

Le dépôt ne cherche pas à déléguer ces responsabilités à Linux.

---

## WSL2 reste la plateforme Linux DevOps

Ubuntu est responsable de :

```text
Bash
Git des projets Linux
Docker Engine
Compose / Buildx
kubectl
Helm
Minikube
kind
Terraform
Ansible
AWS CLI
GitHub CLI
Trivy
outils qualité
```

Contrat actuel :

```text
Ubuntu 26.04
D:\WSL\Ubuntu-DevOps
```

Guide : [`06_WSL2.md`](06_WSL2.md).

---

## Frontière des fichiers

Pour un projet Linux :

```text
~/projects
~/labs
~/repositories
```

Les chemins suivants ne doivent pas devenir les racines de travail principales :

```text
/mnt/c
/mnt/d
```

Un build Linux, Git, Docker ou un gestionnaire de dépendances peut manipuler des milliers de petits fichiers. Le filesystem Linux du VHDX fournit la sémantique et les performances attendues.

Cela n'empêche pas d'accéder ponctuellement aux fichiers Windows depuis WSL.

---

## Terminal et éditeur

```text
WezTerm
├── Ubuntu / Bash DevOps  <- principal pour Linux
└── PowerShell 7          <- administration Windows

VS Code Windows
└── extension WSL
    └── Ubuntu
        └── Bash / outils Linux
```

Le profil shell géré est chargé depuis :

```text
~/.config/windows11-pro-custom/devops.sh
```

Une personnalisation locale non versionnée peut vivre dans :

```text
~/.config/windows11-pro-custom/local.sh
```

Guide : [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md).

---

## OpenClaw

L'intégration optionnelle est isolée sous :

```text
D:\AI\OpenClaw
```

Le projet Windows prépare l'environnement et la qualification ; le dépôt OpenClaw/OpenRouter reste responsable de la logique métier IA.

Guide : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

## Orchestration

```text
état réel
   ↓
Verify
   ↓
plan complet
   ↓
Apply uniquement sur les écarts
   ↓
re-Verify
   ↓
logs / rapports / verdict
```

Le point d'entrée technique principal est `install.ps1`.

Le point d'entrée humain est `menu.ps1`.

Guides : [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) et [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md).

---

## Mises à jour

```text
update.ps1
├── Windows Update
├── WinGet
├── WSL runtime
├── Ubuntu / APT
├── outils DevOps épinglés
└── extensions VS Code
```

Les couches restent séparées : APT ne met pas à jour Windows, WinGet ne choisit pas arbitrairement les versions Terraform, et Windows Update ne doit pas imposer tous les drivers facultatifs.

Guide : [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

## Sauvegarde

```text
État réel de la workstation
│
├── System Restore
│   └── rollback Windows léger
│
├── WindowsImageBackup
│   └── C: + D: + volumes critiques
│
├── export WSL VHDX
│   └── SHA-256
│
└── GitHub
    └── reconstruction du socle versionné
```

La création et la validation peuvent être automatisées. La restauration destructive reste une décision humaine.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

## Sécurité

### Automatisable

- vérifier Secure Boot / TPM / virtualisation ;
- mesurer Defender ;
- appliquer uniquement des exclusions explicitement approuvées ;
- contrôler les versions ;
- créer et vérifier des sauvegardes ;
- vérifier des hashes ;
- produire des plans de reprise.

### Non automatisé par sécurité

- formatage des SSD ;
- flash BIOS ;
- PBO/overclocking ;
- fréquence mémoire forcée ;
- restauration bare-metal ;
- suppression destructive d'une distribution WSL ;
- suppression de données utilisateur/OpenClaw.

---

## Architecture du dépôt

```text
Windows_11_Pro_Custom/
├── README.md
├── START_MENU.cmd
├── menu.ps1
├── install.ps1
├── update.ps1
├── config/
├── manifests/
├── scripts/
│   ├── backup/
│   ├── bootstrap/
│   ├── core/
│   ├── defender/
│   ├── updates/
│   ├── windows/
│   └── wsl/
├── docs/
├── logs/
├── reports/          # créé/alimenté à l'exécution
└── .github/workflows/
```

---

## Sources de vérité

| Besoin | Source principale |
| --- | --- |
| Matériel attendu | politiques de `config/hardware/` |
| WSL version/emplacement | `config/wsl/runtime-contract.json` |
| Ressources WSL | `config/wsl/*.wslconfig` |
| Versions DevOps | `config/devops/tool-versions.env` |
| Logiciels Windows | `manifests/winget/apps-core.json` |
| OpenClaw | `config/openclaw/control-plane.json` |
| Sauvegarde | politique sous `config/backup/` |
| Mises à jour | politique sous `config/updates/` |
| Orchestration | `install.ps1` + `scripts/core/runtime.psm1` |
| Utilisation humaine | `menu.ps1` |

Les suffixes historiques éventuellement présents dans certains noms de fichiers internes sont des détails d'implémentation ; la documentation active décrit **le contrat courant**.

---

## Objectifs architecturaux

1. **Reproductibilité** — reconstruire sans mémoire implicite.
2. **Performance I/O** — Linux travaille sur ext4 dans WSL2.
3. **Sécurité conservée** — pas de debloat destructif.
4. **Idempotence** — ne pas réinstaller ce qui est déjà correct.
5. **Réversibilité** — rollback lorsque l'état initial est fiable.
6. **Observabilité** — logs et rapports persistants.
7. **Disaster recovery** — sauvegarde réelle distincte de Git.
8. **Pédagogie** — comprendre le présent sans devoir apprendre l'historique du dépôt.
