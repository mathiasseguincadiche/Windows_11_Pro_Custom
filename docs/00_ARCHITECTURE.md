# Architecture — Windows 11 Pro Custom

Ce document décrit **où vit chaque composant, qui en est responsable et quelles frontières ne doivent pas être mélangées**.

Pour la documentation complète du projet : [`24_GUIDE_MAITRE_V13.md`](24_GUIDE_MAITRE_V13.md).

---

## 1. Vue d'ensemble

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

---

## 2. Architecture physique du stockage

```text
Crucial T705 #1
└── C: NTFS
    ├── Windows 11 Pro
    ├── applications Windows
    ├── drivers
    └── profils utilisateur

Crucial T705 #2
└── D: NTFS
    ├── DATA
    ├── D:\WSL\Ubuntu-DevOps\...
    ├── D:\WSL\swap\wsl-swap.vhdx
    ├── D:\AI\OpenClaw\...
    ├── ISO
    └── exports / données locales

Disque USB séparé
└── Golden Backup V7
    ├── WindowsImageBackup\
    └── export WSL VHDX + SHA-256
```

### Invariant

Il n'existe **aucune partition EXT4 physique** prévue par le projet.

Le filesystem ext4 Ubuntu se trouve **dans le VHDX WSL2**, lui-même stocké sur `D:` NTFS.

---

## 3. Pourquoi deux SSD ?

### SSD système — `C:`

Responsabilité : Windows et les composants directement liés à l'OS.

### SSD DATA — `D:`

Responsabilité : données lourdes et environnements qui doivent être séparés du volume système :

- WSL2 ;
- OpenClaw ;
- données ;
- ISO ;
- exports.

Cette séparation permet de conserver une architecture compréhensible tout en protégeant `C:` et `D:` ensemble dans le Golden Backup V7.

---

## 4. Windows reste l'hôte

Windows est responsable de :

```text
hardware / drivers
UEFI-facing security state
Windows Update
WinGet
PowerShell
applications graphiques
VS Code UI
WezTerm
OpenClaw Windows
WSL runtime
backup Windows
```

Le dépôt ne cherche pas à remplacer ces responsabilités par des outils Linux.

---

## 5. WSL2 reste la plateforme Linux DevOps

Ubuntu est responsable de :

```text
Bash
Git des projets DevOps
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

Le contrat actuel est :

```text
Ubuntu 26.04 (resolute)
D:\WSL\Ubuntu-DevOps
```

---

## 6. Frontière des fichiers

Pour un projet Linux :

```text
~/projects
~/labs
~/repositories
```

Le contrat interdit comme racines de travail principales :

```text
/mnt/c
/mnt/d
```

### Pourquoi ?

Un build Linux, Git, Docker ou un gestionnaire de dépendances peut manipuler des milliers de petits fichiers. Le filesystem Linux du VHDX offre la sémantique et les performances attendues par ces outils.

Cela n'empêche pas d'accéder ponctuellement aux fichiers Windows depuis WSL.

---

## 7. Architecture terminal / éditeur

```text
WezTerm
├── Ubuntu DevOps / Bash    <- profil principal
└── PowerShell 7            <- profil secondaire

VS Code Windows
└── extension WSL
    └── même Ubuntu
        └── même Bash
            └── même profil DevOps
```

Le profil Bash géré est chargé dans :

```text
~/.config/windows11-pro-custom/devops.sh
```

La personnalisation locale non versionnée peut vivre dans :

```text
~/.config/windows11-pro-custom/local.sh
```

---

## 8. Architecture OpenClaw

```text
D:\AI\OpenClaw\
├── control-plane
├── npm-global
├── state
├── workspace
├── clawops
├── venv
├── logs
└── cache
```

OpenClaw est volontairement Windows-native, tandis que WSL fournit le backend DevOps Linux.

La source de code OpenClaw approuvée est épinglée par SHA via :

```text
config/openclaw/control-plane.json
```

---

## 9. Architecture d'orchestration

Le point d'entrée technique principal est `install.ps1`.

V9 suit :

```text
DISCOVERY
   ↓
faits machine
   ↓
VERIFY de chaque composant
   ↓
PLAN COMPLET
   ↓
confirmation
   ↓
point de restauration / mesure avant si changement
   ↓
APPLY uniquement pour les écarts
   ↓
RE-VERIFY
   ↓
mesure après / logs / rapports
```

Le plan est calculé avant la première mutation.

---

## 10. Architecture du menu V12

```text
START_MENU.cmd
      ↓
menu.ps1
      ├── install.ps1
      ├── update.ps1
      └── composants spécialisés existants
```

Le menu ne possède pas sa propre logique d'installation : il route vers les mécanismes déjà testés.

---

## 11. Architecture des mises à jour V11

```text
update.ps1
├── Windows Update
├── WinGet
├── WSL runtime
├── Ubuntu / APT
├── DevOps pinned
└── VS Code extensions
```

Les couches restent séparées : APT ne met pas à jour Windows, WinGet ne décide pas des versions Terraform épinglées, et Windows Update n'est pas autorisé à imposer les drivers facultatifs par défaut.

---

## 12. Architecture de sauvegarde V7

```text
État réel de la workstation
│
├── System Restore
│   └── rollback Windows léger
│
├── WindowsImageBackup
│   └── C: + D: + volumes critiques
│
├── WSL export VHDX
│   └── SHA-256
│
└── GitHub
    └── reconstruction du socle versionné
```

La création et la validation sont automatisées. La restauration destructive reste humaine.

---

## 13. Architecture de sécurité

### Automatisable

- vérifier Secure Boot / TPM / virtualisation ;
- mesurer Defender ;
- appliquer uniquement des exclusions explicitement approuvées ;
- contrôler les versions ;
- créer des backups ;
- vérifier des hashes ;
- créer un plan de reprise.

### Non automatisé par sécurité

- formatage des SSD ;
- flash BIOS ;
- PBO/overclocking ;
- forçage RAM 6000 ;
- restauration bare-metal ;
- `wsl --unregister` de la distribution active ;
- suppression des données OpenClaw.

---

## 14. Architecture du dépôt

```text
Windows_11_Pro_Custom/
├── README.md
├── START_MENU.cmd
├── menu.ps1
├── install.ps1
├── update.ps1
├── config/
│   ├── backup/
│   ├── defender/
│   ├── devops/
│   ├── hardware/
│   ├── openclaw/
│   ├── orchestration/
│   ├── updates/
│   ├── vscode/
│   ├── wezterm/
│   ├── windows/
│   └── wsl/
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

## 15. Où regarder selon le problème ?

| Problème | Source de vérité principale |
|---|---|
| Matériel attendu | `config/hardware/target-v5.json` |
| WSL version/emplacement | `config/wsl/runtime-contract.json` |
| Ressources WSL | `config/wsl/*.wslconfig` |
| Versions DevOps | `config/devops/tool-versions.env` |
| Logiciels Windows | `manifests/winget/apps-core.json` |
| OpenClaw | `config/openclaw/control-plane.json` |
| Backup | `config/backup/v7-policy.json` |
| Updates | `config/updates/v11.json` |
| Orchestration | `install.ps1` + `scripts/core/runtime.psm1` |
| Utilisation humaine | `menu.ps1` |

---

## 16. Objectifs architecturaux

1. **Reproductibilité** — reconstruire sans mémoire implicite.
2. **Performance I/O** — Linux travaille sur ext4 dans WSL.
3. **Sécurité conservée** — pas de debloat destructif ni de protection désactivée sans preuve.
4. **Idempotence** — ne pas réinstaller ce qui est déjà correct.
5. **Réversibilité** — rollback lorsqu'un état initial fiable existe.
6. **Observabilité** — logs et rapports persistants.
7. **Disaster recovery** — sauvegarde réelle distincte du dépôt Git.
8. **Pédagogie** — un débutant peut suivre la procédure sans connaître l'historique V1→V12.
