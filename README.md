# Windows 11 Pro Custom — workstation DevOps/Ops reproductible

[![Qualité](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/quality.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/quality.yml)
[![Runtime WSL](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/wsl-runtime-contract.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/wsl-runtime-contract.yml)
[![Documentation](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/documentation.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/documentation.yml)

`Windows_11_Pro_Custom` définit, automatise, vérifie et documente **une workstation Windows 11 Pro de référence pour DevOps/Ops**.

Ce dépôt n'est ni un script de « debloat », ni une liste de logiciels, ni un historique de réglages personnels. C'est une **workstation-as-code** : l'état attendu est versionné, la machine réelle est observée avant modification, seuls les écarts utiles sont corrigés, puis le résultat est re-vérifié et documenté.

> **Objectif :** pouvoir partir d'un Windows propre ou d'une machine déjà utilisée, reconstruire la même architecture, comprendre ce qui est conforme, appliquer uniquement ce qui manque, valider la workstation et conserver une sauvegarde de référence exploitable.

## En 60 secondes

Le projet organise la machine ainsi :

```text
Windows 11 Pro
├── desktop / gaming / pilotes / sécurité
├── PowerShell 7 / VS Code / WezTerm
├── Windows Update / WinGet / sauvegarde
└── WSL2
    └── Ubuntu 26.04
        ├── Bash / Git
        ├── Docker / Kubernetes
        ├── Terraform / Ansible
        ├── AWS / GitHub CLI
        └── outils qualité

D:\AI\OpenClaw
└── intégration IA optionnelle Windows-native
```

La règle structurante est simple :

```text
Windows gère l'expérience Windows.
Linux gère les workloads Linux.
```

Les projets Linux actifs vivent donc sur le filesystem ext4 de WSL2, sous `~/projects`, `~/labs` ou `~/repositories`, et non sous `/mnt/c` ou `/mnt/d` comme racine de travail quotidienne.

---

## Ce que le projet garantit

Le dépôt cherche à produire une machine :

- **reproductible** — les choix importants sont dans Git ;
- **idempotente** — un composant déjà conforme n'est pas réinstallé inutilement ;
- **vérifiable** — `Verify` et les validateurs spécialisés déterminent le résultat réel ;
- **explicable** — logs et rapports permettent de comprendre ce qui a été observé et exécuté ;
- **sécurisée** — Defender, firewall, Windows Update, Secure Boot et TPM ne sont pas sacrifiés pour gagner quelques points de benchmark ;
- **récupérable** — backup et reprise après incident font partie du projet ;
- **adaptée au matériel réel** — la qualification tient compte de la workstation cible.

Le projet préfère une `ACTION_REQUISE` honnête à un faux succès lorsqu'une preuve BIOS, matérielle ou humaine ne peut pas être automatisée.

---

## Architecture de référence

### Stockage

```text
SSD système
└── C: NTFS
    └── Windows 11 Pro + applications + profil utilisateur

SSD données / environnements
└── D: NTFS
    ├── D:\WSL\Ubuntu-DevOps
    ├── D:\WSL\swap\wsl-swap.vhdx
    ├── D:\AI\OpenClaw
    └── données / exports

Support externe séparé
└── sauvegarde de référence
```

Il n'existe **aucune partition EXT4 physique** prévue par le projet. Ubuntu utilise ext4 à l'intérieur de son VHDX WSL2 stocké sur `D:` NTFS.

### WSL2

Le contrat quotidien actuel est :

```text
Distribution : Ubuntu 26.04
Nom          : Ubuntu
Emplacement  : D:\WSL\Ubuntu-DevOps
RAM          : 20 Go
CPU          : 8 threads
Swap         : 8 Go
Réseau       : mirrored
```

Un profil plus lourd existe pour les labs qui en ont réellement besoin ; il ne devient pas le profil par défaut.

### DevOps

Ubuntu fournit la couche Linux de travail : Docker Engine, Compose, Buildx, kubectl, Helm, Minikube, kind, Terraform, Ansible, AWS CLI, GitHub CLI, Trivy et les outils qualité gérés par le dépôt.

Les versions sensibles à la reproductibilité sont définies par les contrats du dépôt ; une version `latest` disponible sur Internet n'écrase pas automatiquement une cible validée.

---

## Comment le projet agit sur la machine

Le moteur principal est `install.ps1`.

```text
état réel
   ↓
Verify
   ↓
plan factuel
   ↓
confirmation
   ↓
Apply uniquement sur les écarts
   ↓
re-Verify
   ↓
logs / rapports / verdict
```

Les fichiers d'état, les anciens logs ou le simple fait qu'un script ait déjà été lancé ne constituent pas une preuve de conformité. La source de décision reste l'état réellement observé face aux contrats actuels.

Les points d'entrée sont :

```text
START_MENU.cmd / menu.ps1  -> interface humaine
install.ps1                -> audit / convergence / validation / rollback / backup
update.ps1                 -> maintenance de la workstation
```

---

## Réaliser le projet

### 1. Auditer la machine

```powershell
.\install.ps1 -Mode Audit
```

Cette étape observe avant de modifier.

### 2. Prévisualiser la convergence complète

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Le plan doit distinguer ce qui est déjà conforme de ce qui doit réellement changer.

### 3. Appliquer les écarts

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

### 4. Valider le résultat

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

OpenClaw est validé séparément uniquement lorsque cette intégration est utilisée.

### 5. Prouver l'idempotence

Relancer le plan :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Une workstation stable doit tendre vers `DÉJÀ OK` pour les composants déjà conformes.

### 6. Sauvegarder

Une fois la workstation validée, créer puis vérifier une sauvegarde de référence sur un support séparé. Les commandes et garde-fous sont détaillés dans la documentation dédiée.

Le parcours complet est dans [`docs/20_RUNBOOK_OPERATIONNEL.md`](docs/20_RUNBOOK_OPERATIONNEL.md).

---

## Quand le projet est-il terminé ?

Le projet n'est pas « terminé » parce que `Apply` s'est exécuté sans exception.

Le résultat attendu est :

```text
contrats compris
+
plan cohérent
+
convergence réussie
+
Windows conforme
+
matériel qualifié
+
WSL2 conforme
+
stack DevOps conforme
+
idempotence démontrée
+
preuves exploitables
+
sauvegarde vérifiée
```

La checklist officielle est [`docs/24_CRITERES_ACCEPTATION.md`](docs/24_CRITERES_ACCEPTATION.md).

---

## Ce que le dépôt ne fait volontairement pas

Pour conserver une frontière de sécurité claire, le projet ne doit pas automatiser aveuglément :

- le formatage ou l'effacement des SSD ;
- une restauration bare-metal destructive ;
- la suppression destructive d'une distribution WSL ;
- un flash BIOS ou firmware ;
- PBO, Curve Optimizer ou overclocking ;
- des timings mémoire forcés ;
- la désactivation de Defender, du firewall ou de Windows Update ;
- la suppression massive de composants Windows pour « debloat » ;
- le remplacement des versions DevOps validées par `latest` sans décision explicite.

Ces limites font partie de l'architecture, pas d'un manque d'automatisation.

---

## Documentation officielle

Le README reste volontairement synthétique. Le détail technique est dans [`docs/README.md`](docs/README.md).

| Besoin | Document |
| --- | --- |
| Comprendre l'architecture | [`docs/00_ARCHITECTURE.md`](docs/00_ARCHITECTURE.md) |
| Installer Windows depuis zéro | [`docs/01_INSTALLATION_WINDOWS.md`](docs/01_INSTALLATION_WINDOWS.md) |
| Comprendre WSL2 | [`docs/06_WSL2.md`](docs/06_WSL2.md) |
| Apprendre WSL2 depuis les bases | [`docs/16_WSL2_GUIDE_COMPLET.md`](docs/16_WSL2_GUIDE_COMPLET.md) |
| Comprendre la stack DevOps | [`docs/07_DEVOPS_STACK.md`](docs/07_DEVOPS_STACK.md) |
| Comprendre l'orchestration | [`docs/14_ORCHESTRATION.md`](docs/14_ORCHESTRATION.md) |
| Réaliser le projet de A à Z | [`docs/20_RUNBOOK_OPERATIONNEL.md`](docs/20_RUNBOOK_OPERATIONNEL.md) |
| Référence des commandes | [`docs/21_REFERENCE_COMMANDES.md`](docs/21_REFERENCE_COMMANDES.md) |
| Dépanner | [`docs/22_TROUBLESHOOTING.md`](docs/22_TROUBLESHOOTING.md) |
| Identifier la source de vérité | [`docs/23_SOURCES_DE_VERITE.md`](docs/23_SOURCES_DE_VERITE.md) |
| Valider la fin du projet | [`docs/24_CRITERES_ACCEPTATION.md`](docs/24_CRITERES_ACCEPTATION.md) |
| Sauvegarder / restaurer | [`docs/10_BACKUP_RESTORE.md`](docs/10_BACKUP_RESTORE.md) |
| Reconstruire après incident | [`docs/13_RUNBOOK_REINSTALLATION.md`](docs/13_RUNBOOK_REINSTALLATION.md) |
| Intégrer OpenClaw/OpenRouter | [`docs/19_OPENCLAW_OPENROUTER_WINDOWS.md`](docs/19_OPENCLAW_OPENROUTER_WINDOWS.md) |

La documentation active décrit **l'état actuel**. `CHANGELOG.md` conserve l'historique fonctionnel et Git conserve le détail des évolutions.

---

## Organisation du dépôt

```text
Windows_11_Pro_Custom/
├── README.md
├── START_MENU.cmd
├── menu.ps1
├── install.ps1
├── update.ps1
├── config/       # contrats et politiques
├── manifests/    # catalogues déclaratifs
├── scripts/      # implémentation
├── docs/         # documentation technique officielle
├── logs/         # preuves d'exécution
├── reports/      # états et synthèses produits à l'exécution
└── .github/workflows/
```

En cas de divergence entre documentation et implémentation, consulter [`docs/23_SOURCES_DE_VERITE.md`](docs/23_SOURCES_DE_VERITE.md) : la documentation explique le projet, mais elle ne doit jamais inventer un comportement absent du code ou contredire un contrat machine-readable.