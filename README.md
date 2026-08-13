# Windows 11 Pro Custom — workstation DevOps/Ops reproductible

[![Qualité](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/quality.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/quality.yml)
[![Runtime WSL](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/wsl-runtime-contract.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/wsl-runtime-contract.yml)

**Windows 11 Pro Custom** est la configuration versionnée de ma workstation personnelle : un poste Windows 11 Pro pensé pour **DevOps/Ops**, WSL2, administration système, développement d'infrastructure, usage desktop quotidien et gaming.

Le but n'est pas d'empiler des scripts ou de transformer Windows en Linux. Le but est de construire une machine **cohérente, performante, vérifiable, maintenable et récupérable** dont les choix importants sont documentés et reproductibles.

> **L'essence du projet :** pouvoir repartir d'un Windows propre, retrouver la même architecture, les mêmes outils et les mêmes garde-fous, vérifier l'état réel de la machine, corriger uniquement ce qui manque, puis conserver une stratégie de sauvegarde et de reprise exploitable.

Les scripts sont le **moyen d'automatiser cette workstation**. Ils ne sont pas le sujet principal du README.

---

## Ce que construit le projet

La workstation combine plusieurs usages sans mélanger leurs responsabilités :

```text
                    MATÉRIEL CIBLE
                         │
                         ▼
                   Windows 11 Pro
          ┌──────────────┼──────────────┐
          │              │              │
          ▼              ▼              ▼
     Desktop/gaming   Administration   WSL2 / Ubuntu
     applications     PowerShell 7       │
     pilotes          Windows Update     ▼
     VS Code UI       sécurité       Linux DevOps
     WezTerm          sauvegarde     Docker / K8s
          │                           Terraform
          │                           Ansible / AWS
          └──────────────┬──────────────┘
                         ▼
                workstation cohérente
                         │
        audit → convergence → validation
                         │
                         ▼
                 sauvegarde / reprise
```

Concrètement, le dépôt gère ou documente :

- l'architecture Windows 11 Pro et des deux SSD ;
- le matériel cible et sa qualification ;
- les applications Windows ;
- PowerShell 7, VS Code, WezTerm et OpenSSH Client ;
- WSL2 avec Ubuntu 26.04 ;
- Docker, Kubernetes, Terraform, Ansible, AWS CLI et outils qualité ;
- les réglages Windows mesurés et réversibles ;
- Microsoft Defender sans exclusions agressives ;
- les mises à jour de la workstation ;
- les journaux, audits et validations ;
- la sauvegarde Windows + WSL2 et le plan de reprise ;
- l'intégration optionnelle d'OpenClaw/OpenRouter sur `D:`.

---

## Philosophie : une workstation-as-code

Le dépôt applique à un poste personnel des principes proches de l'Infrastructure as Code :

```text
configuration versionnée
        +
état réel de la machine
        ↓
observation
        ↓
comparaison
        ↓
action minimale
        ↓
re-vérification
        ↓
preuve / journal / rapport
```

Cela implique plusieurs règles importantes.

### Machine-first

La machine est inspectée avant de décider qu'une action est nécessaire.

### Idempotence

Si un composant est déjà conforme, il ne doit pas être réinstallé ou modifié inutilement.

### Réversibilité

Lorsqu'un état initial fiable peut être capturé, les réglages gérés disposent d'un rollback.

### Sécurité conservée

La performance ne justifie pas de désactiver Defender, Windows Update, le firewall, Secure Boot, TPM, WSL/Hyper-V ou d'autres briques nécessaires au système.

### Matériel-aware

La configuration tient compte du matériel réel au lieu d'appliquer des valeurs génériques prévues pour n'importe quel PC.

### Recovery-first

Une configuration parfaite n'est pas suffisante si elle ne peut pas être restaurée après une panne ou une réinstallation.

---

## Matériel cible

| Composant | Configuration |
| --- | --- |
| CPU | AMD Ryzen 7 7700 — 8 cœurs / 16 threads |
| Carte mère | MSI MAG B850M Mortar WiFi |
| RAM | 48 Go DDR5 — 6000 MT/s uniquement si stable |
| GPU | Intel Arc B580 12 Go |
| SSD système | Crucial T705 PCIe 5.0 |
| SSD DATA / WSL | Crucial T705 PCIe 5.0 |
| Refroidissement | DeepCool LD240WH |
| Alimentation | Corsair RM650e 650 W |
| Boîtier | ASUS Prime AP201 |
| Affichage | 2560×1440 à haut taux de rafraîchissement |

Le dépôt **qualifie** ce matériel mais ne modifie jamais automatiquement le BIOS, PBO, Curve Optimizer, la fréquence mémoire, ReBAR, les slots M.2 ou le firmware SSD.

Guide : [`docs/12_HARDWARE_QUALIFICATION.md`](docs/12_HARDWARE_QUALIFICATION.md).

---

## Architecture de stockage

Les deux SSD restent sous contrôle de Windows :

```text
Crucial T705 #1
└── C: NTFS
    ├── Windows 11 Pro
    ├── applications
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

Disque USB NTFS séparé
└── sauvegarde de référence
```

Il n'y a **ni dual boot ni partition EXT4 physique** prévue par le projet.

Ubuntu possède bien un filesystem Linux ext4, mais il se trouve **dans son VHDX WSL2**, stocké sur le second SSD NTFS.

Guide : [`docs/03_STOCKAGE.md`](docs/03_STOCKAGE.md).

---

## Windows reste l'hôte, WSL2 devient le backend Linux

La séparation des rôles est volontaire.

### Windows 11 Pro

Windows reste responsable de :

- l'interface graphique ;
- les pilotes et périphériques ;
- les navigateurs et logiciels desktop ;
- Steam et le gaming ;
- PowerShell 7 ;
- VS Code côté interface ;
- WezTerm ;
- Windows Update et WinGet ;
- Microsoft Defender ;
- le runtime WSL ;
- les sauvegardes Windows.

### Ubuntu WSL2

Ubuntu fournit l'environnement Linux DevOps :

- Bash ;
- Git ;
- Docker Engine, Compose et Buildx ;
- kubectl et Helm ;
- Minikube et kind ;
- Terraform ;
- Ansible ;
- AWS CLI ;
- GitHub CLI ;
- Trivy et outils qualité IaC/shell.

La règle de travail est simple :

```text
outils Linux → fichiers Linux
```

Les projets DevOps actifs vivent donc dans :

```text
/home/<user>/projects
/home/<user>/labs
/home/<user>/repositories
```

et non dans `/mnt/c` ou `/mnt/d` comme racine de travail quotidienne.

Guides : [`docs/06_WSL2.md`](docs/06_WSL2.md) et [`docs/07_DEVOPS_STACK.md`](docs/07_DEVOPS_STACK.md).

---

## WSL2 adapté au Ryzen 7 7700 et aux 48 Go de RAM

Le profil quotidien laisse volontairement une vraie réserve à Windows :

```text
Ubuntu 26.04
20 Go RAM
8 threads
8 Go swap
réseau mirrored
DNS tunneling
firewall WSL/Hyper-V actif
autoMemoryReclaim progressif
```

Un profil plus lourd est disponible pour les labs Kubernetes ou les builds exigeants, sans devenir le profil par défaut.

Cette approche évite qu'un cluster local ou une compilation monopolise la workstation alors que Windows, VS Code, les navigateurs ou les applications desktop ont encore besoin de ressources.

Le guide pédagogique WSL2 complet est disponible dans [`docs/16_WSL2_GUIDE_COMPLET.md`](docs/16_WSL2_GUIDE_COMPLET.md).

---

## Une vraie workstation DevOps, pas seulement WSL2 installé

La stack Linux est conçue pour travailler réellement :

```text
Docker Engine
Docker Compose / Buildx
kubectl / Helm
Minikube / kind
Terraform
Ansible
AWS CLI
GitHub CLI
Trivy
ShellCheck / shfmt
actionlint / TFLint / terraform-docs / yq
```

Les composants sensibles à la reproductibilité sont épinglés par le dépôt au lieu d'être remplacés aveuglément par `latest`.

WezTerm ouvre Ubuntu/Bash comme terminal DevOps principal et conserve PowerShell 7 comme terminal Windows. VS Code utilise le même environnement WSL lorsque le projet est Linux.

---

## Windows optimisé sans « debloat » destructif

L'objectif est une machine réactive, propre et prévisible, pas un Windows amputé de composants critiques.

Le dépôt peut gérer des réglages liés à :

- bruit et suggestions Windows ;
- confidentialité ;
- gaming ;
- réactivité de l'interface ;
- comportement de certains services ciblés ;
- benchmark léger avant/après.

Mais il refuse les recettes agressives du type :

```text
Defender OFF
Windows Update OFF
pagefile OFF
memory compression OFF
services désactivés en masse
HPET/BCD tweak aléatoire
SSD benchmark d'écriture massif
```

Les changements gérés sont bornés, vérifiables et rollbackables lorsque cela est raisonnable.

Guide : [`docs/04_OPTIMISATION_WINDOWS.md`](docs/04_OPTIMISATION_WINDOWS.md).

---

## Defender reste actif

Microsoft Defender est une partie normale de la workstation.

Les exclusions suivent une politique **deny-by-default** : aucune exclusion large n'est ajoutée simplement parce que Docker, WSL ou un projet génère beaucoup d'I/O.

Si un hotspot réel est mesuré, une exclusion peut être évaluée et explicitement approuvée.

Guide : [`docs/05_DEFENDER_PERFORMANCE.md`](docs/05_DEFENDER_PERFORMANCE.md).

---

## Applications Windows

Le socle applicatif comprend notamment :

- Visual Studio Code ;
- PowerShell 7 ;
- WezTerm ;
- Firefox / Brave ;
- VLC ;
- Notion ;
- FileZilla ;
- LibreOffice ;
- Steam ;
- Notepad++ ;
- draw.io ;
- Bitwarden ;
- JetBrainsMono Nerd Font.

Les applications disposant d'un identifiant WinGet fiable peuvent être automatisées. Les logiciels dont l'installation n'est pas suffisamment fiable restent manuels plutôt que simulés par une automatisation fragile.

Guide : [`docs/08_APPLICATIONS.md`](docs/08_APPLICATIONS.md).

---

## Sauvegarde et reprise après incident

GitHub protège le **socle versionné**, pas la machine réelle.

La protection de la workstation repose sur plusieurs niveaux :

```text
System Restore
        ↓
rollback Windows léger

WindowsImageBackup
        ↓
C: + D: + volumes critiques

Export WSL VHDX + SHA-256
        ↓
Ubuntu restaurable séparément

GitHub
        ↓
reconstruction du socle automatisé
```

La cible de sauvegarde de référence est un **disque USB NTFS séparé** des deux SSD internes.

Le dépôt peut créer, vérifier et préparer une restauration, mais **ne déclenche jamais automatiquement une restauration bare-metal destructive**.

Guide : [`docs/10_BACKUP_RESTORE.md`](docs/10_BACKUP_RESTORE.md).

---

## Maintenance et mises à jour

La workstation possède plusieurs domaines de maintenance qui doivent rester distincts :

```text
Windows Update
WinGet
WSL runtime
Ubuntu / APT
outils DevOps épinglés
extensions VS Code
```

Le dépôt coordonne ces couches sans forcer de reboot, de flash firmware, de changement majeur Ubuntu ou de mise à jour arbitraire d'un outil DevOps.

Guide : [`docs/15_MISES_A_JOUR.md`](docs/15_MISES_A_JOUR.md).

---

## OpenClaw / OpenRouter

L'intégration OpenClaw est optionnelle et isolée sous :

```text
D:\AI\OpenClaw
```

Elle complète la workstation mais **ne définit pas le projet Windows**. Le dépôt `openclaw_openrouter` reste responsable du fonctionnement métier d'OpenClaw/OpenRouter ; ce dépôt Windows prépare uniquement l'environnement et les points d'intégration nécessaires.

Guide : [`docs/19_OPENCLAW_OPENROUTER_WINDOWS.md`](docs/19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

## Utiliser le dépôt

### Pour comprendre avant d'installer

Commencer par :

1. [`docs/README.md`](docs/README.md) ;
2. [`docs/00_ARCHITECTURE.md`](docs/00_ARCHITECTURE.md) ;
3. [`docs/18_GUIDE_MAITRE.md`](docs/18_GUIDE_MAITRE.md).

### Pour installer Windows depuis zéro

Le guide dédié est :

[`docs/01_INSTALLATION_WINDOWS.md`](docs/01_INSTALLATION_WINDOWS.md).

L'installation est volontairement **une section du projet**, pas le contenu principal de ce README.

### Pour piloter une machine déjà installée

L'interface humaine est :

```text
START_MENU.cmd
```

ou :

```powershell
.\menu.ps1
```

Le centre de contrôle route vers les orchestrateurs existants pour l'installation, la réparation, les mises à jour, les audits, la sauvegarde et les validations.

Guide : [`docs/17_CONTROL_CENTER.md`](docs/17_CONTROL_CENTER.md).

### Pour comprendre l'orchestration

```powershell
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Apply
.\install.ps1 -Mode Verify
.\install.ps1 -Mode Rollback
```

Guide : [`docs/14_ORCHESTRATION.md`](docs/14_ORCHESTRATION.md).

---

## Validation

Le dépôt ne considère pas qu'une installation est réussie uniquement parce qu'une commande s'est terminée.

La logique de validation est :

```text
contrat attendu
+
état réellement observé
+
preuve disponible
+
Verify réussi
```

Une validation complète peut couvrir le matériel, WSL2 et la stack DevOps :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

OpenClaw peut être vérifié séparément lorsque cette intégration est utilisée.

Guide : [`docs/11_VALIDATION.md`](docs/11_VALIDATION.md).

---

## Documentation

La documentation active est organisée par responsabilité, pas par ancienne version du projet :

| Document | Rôle |
| --- | --- |
| [`docs/00_ARCHITECTURE.md`](docs/00_ARCHITECTURE.md) | architecture globale et frontières Windows/Linux |
| [`docs/01_INSTALLATION_WINDOWS.md`](docs/01_INSTALLATION_WINDOWS.md) | installation Windows depuis zéro |
| [`docs/02_BIOS_DRIVERS.md`](docs/02_BIOS_DRIVERS.md) | UEFI, BIOS et stratégie pilotes |
| [`docs/03_STOCKAGE.md`](docs/03_STOCKAGE.md) | organisation des SSD et fichiers |
| [`docs/04_OPTIMISATION_WINDOWS.md`](docs/04_OPTIMISATION_WINDOWS.md) | optimisation et réactivité Windows |
| [`docs/05_DEFENDER_PERFORMANCE.md`](docs/05_DEFENDER_PERFORMANCE.md) | Defender et performance |
| [`docs/06_WSL2.md`](docs/06_WSL2.md) | configuration WSL2 actuelle |
| [`docs/07_DEVOPS_STACK.md`](docs/07_DEVOPS_STACK.md) | environnement Linux DevOps et terminal |
| [`docs/08_APPLICATIONS.md`](docs/08_APPLICATIONS.md) | applications Windows |
| [`docs/09_GAMING_OLED.md`](docs/09_GAMING_OLED.md) | gaming et affichage |
| [`docs/10_BACKUP_RESTORE.md`](docs/10_BACKUP_RESTORE.md) | sauvegarde et reprise |
| [`docs/11_VALIDATION.md`](docs/11_VALIDATION.md) | validation de la workstation |
| [`docs/12_HARDWARE_QUALIFICATION.md`](docs/12_HARDWARE_QUALIFICATION.md) | qualification matérielle |
| [`docs/13_RUNBOOK_REINSTALLATION.md`](docs/13_RUNBOOK_REINSTALLATION.md) | reconstruction complète |
| [`docs/14_ORCHESTRATION.md`](docs/14_ORCHESTRATION.md) | convergence et idempotence |
| [`docs/15_MISES_A_JOUR.md`](docs/15_MISES_A_JOUR.md) | maintenance de la plateforme |
| [`docs/16_WSL2_GUIDE_COMPLET.md`](docs/16_WSL2_GUIDE_COMPLET.md) | guide pédagogique WSL2 |
| [`docs/17_CONTROL_CENTER.md`](docs/17_CONTROL_CENTER.md) | menu interactif |
| [`docs/18_GUIDE_MAITRE.md`](docs/18_GUIDE_MAITRE.md) | compréhension complète du projet |
| [`docs/19_OPENCLAW_OPENROUTER_WINDOWS.md`](docs/19_OPENCLAW_OPENROUTER_WINDOWS.md) | intégration OpenClaw/OpenRouter |

L'historique des évolutions reste dans [`CHANGELOG.md`](CHANGELOG.md). Il n'est plus utilisé comme structure de la documentation actuelle.

---

## Limites volontaires

Le dépôt ne doit jamais automatiquement :

- formater un SSD ;
- flasher le BIOS/UEFI ;
- forcer PBO, overclocking ou timings RAM ;
- désactiver Defender globalement ;
- désactiver Windows Update ;
- appliquer des exclusions Defender larges non mesurées ;
- supprimer massivement des composants Windows ;
- déplacer les projets Linux actifs vers `/mnt/c` ou `/mnt/d` ;
- remplacer les versions DevOps qualifiées par `latest` ;
- forcer un redémarrage ;
- lancer une restauration bare-metal destructive ;
- supprimer automatiquement la distribution WSL active ;
- publier des secrets dans Git.

---

## Résultat attendu

À la fin, la workstation doit être compréhensible comme un système complet :

```text
Windows 11 Pro stable et agréable
+
matériel qualifié
+
WSL2 correctement dimensionné
+
stack DevOps Linux complète
+
applications et terminal cohérents
+
optimisations mesurées et sûres
+
validation factuelle
+
maintenance maîtrisée
+
sauvegarde réellement exploitable
```

C'est cette cohérence globale — et non la quantité de scripts — qui définit **Windows 11 Pro Custom**.
