# Windows 11 Pro Custom — workstation DevOps/Ops reproductible

[![Qualité](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/quality.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/quality.yml)
[![Runtime WSL](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/wsl-runtime-contract.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/wsl-runtime-contract.yml)
[![Documentation](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/documentation.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/documentation.yml)

`Windows_11_Pro_Custom` construit, vérifie et maintient **une workstation Windows 11 Pro de référence pour DevOps/Ops**.

Le projet applique une approche **workstation-as-code** : il observe d'abord l'état réel de la machine, le compare à des contrats versionnés, applique uniquement les écarts nécessaires, puis vérifie le résultat. L'objectif n'est pas de « lancer une suite de scripts », mais d'obtenir une machine **reproductible, compréhensible, maintenable et récupérable**.

> **En une phrase :** ce dépôt transforme une installation Windows 11 Pro propre ou partiellement configurée en une workstation DevOps/Ops cohérente, sans masquer les décisions humaines ni les opérations potentiellement destructives.

## À qui s'adresse ce projet ?

Ce dépôt est utile si vous souhaitez :

- utiliser **Windows 11 Pro comme hôte principal** ;
- disposer d'un **backend Linux DevOps sous WSL2 Ubuntu 26.04** ;
- séparer clairement administration Windows et workloads Linux ;
- automatiser l'installation, la convergence, la validation et la maintenance ;
- conserver des preuves d'exécution, une baseline de référence et une stratégie de reprise ;
- pouvoir relancer les opérations sans réinstaller inutilement ce qui est déjà conforme.

Si vous découvrez WSL2, l'idempotence, les baselines ou la notion de drift, commencez par [`docs/18_GUIDE_MAITRE.md`](docs/18_GUIDE_MAITRE.md) et le [`glossaire`](docs/GLOSSAIRE.md).

## Ce que le projet construit

```text
Windows 11 Pro
│
├── Hôte Windows
│   ├── sécurité / Windows Update / Defender
│   ├── pilotes et qualification matérielle
│   ├── PowerShell 7 / WinGet
│   ├── VS Code
│   └── Windows Terminal
│       ├── PowerShell 7 - DevOps
│       └── Ubuntu - DevOps
│
└── WSL2
    └── Ubuntu 26.04
        ├── filesystem Linux ext4
        ├── Docker / Kubernetes
        ├── Terraform / Ansible / AWS
        └── workspaces DevOps
```

La séparation est volontaire :

```text
Windows          = hôte, desktop, pilotes, sécurité et administration
Ubuntu           = backend Linux DevOps et workspaces Linux
Windows Terminal = routeur vers PowerShell 7 - DevOps et Ubuntu - DevOps
VS Code          = interface Windows reliée aux projets WSL2
```

Les projets Linux actifs restent dans le filesystem Linux :

```text
~/projects
~/labs
~/repositories
```

`/mnt/c` et `/mnt/e` restent utiles pour des échanges ponctuels avec Windows, mais ne sont pas les racines de travail quotidiennes recommandées pour des projets principalement exécutés sous Linux.

## Principes fondamentaux

Le comportement attendu peut se résumer ainsi :

1. **Observer avant de modifier.**
2. **Comparer l'état réel à une source de vérité versionnée.**
3. **Modifier uniquement ce qui n'est pas conforme.**
4. **Vérifier après modification.**
5. **Distinguer preuve automatique et preuve humaine.**
6. **Conserver les actions destructives sous contrôle explicite.**
7. **Pouvoir relancer le même parcours sans effets inutiles.**

C'est le cœur de l'idempotence du projet.

## Ce qui est géré — et ce qui ne l'est pas

| Géré par ce dépôt | Hors périmètre ou décision humaine |
| --- | --- |
| configuration et validation Windows | flash BIOS/UEFI automatique |
| applications WinGet déclarées | partitionnement destructif automatique |
| WSL2 Ubuntu et son contrat | overclocking CPU/GPU |
| stack DevOps Linux | saisie et stockage de secrets |
| Windows Terminal et VS Code | restauration bare-metal automatique |
| qualification matérielle | décisions physiques ambiguës |
| sauvegarde, vérification et plans de reprise | projets applicatifs externes |
| maintenance structurée | OpenClaw/OpenRouter |

`Windows_11_Pro_Custom` **n'installe pas, ne configure pas, ne met pas à jour et ne valide pas OpenClaw/OpenRouter**. La plateforme IA appartient au dépôt autonome `mathiasseguincadiche/openclaw_openrouter`.

## Contrats essentiels

### Stockage

```text
C: NTFS -> Windows 11 Pro et composants système
E: NTFS -> données, WSL2, ISO et exports
```

WSL2 stocke son environnement Linux sous :

```text
E:\WSL\Ubuntu-DevOps
```

Le filesystem Linux ext4 se trouve **dans le VHDX WSL2** ; aucune partition ext4 physique supplémentaire n'est requise.

### WSL2

Le profil standard actuel est :

```text
Distribution : Ubuntu
Release      : Ubuntu 26.04
Emplacement  : E:\WSL\Ubuntu-DevOps
RAM          : 20 Go
CPU          : 8 threads
Swap         : 8 Go
Réseau       : mirrored
```

Les autres profils autorisés et leur rôle sont documentés dans [`docs/06_WSL2.md`](docs/06_WSL2.md).

## Par où commencer ?

| Situation | Parcours conseillé |
| --- | --- |
| Je découvre le projet | ce README → [`docs/18_GUIDE_MAITRE.md`](docs/18_GUIDE_MAITRE.md) → [`docs/00_ARCHITECTURE.md`](docs/00_ARCHITECTURE.md) |
| Je pars d'un Windows vierge | [`docs/01_INSTALLATION_WINDOWS.md`](docs/01_INSTALLATION_WINDOWS.md) → [`docs/20_RUNBOOK_OPERATIONNEL.md`](docs/20_RUNBOOK_OPERATIONNEL.md) |
| Ma machine existe déjà | Audit → identité stockage → PlanOnly → Apply → Verify |
| Je veux comprendre WSL2 | [`docs/16_WSL2_GUIDE_COMPLET.md`](docs/16_WSL2_GUIDE_COMPLET.md) |
| Je cherche une commande exacte | [`docs/21_REFERENCE_COMMANDES.md`](docs/21_REFERENCE_COMMANDES.md) |
| J'ai un problème | [`docs/22_TROUBLESHOOTING.md`](docs/22_TROUBLESHOOTING.md) |
| Je dois reconstruire après incident | [`docs/13_RUNBOOK_REINSTALLATION.md`](docs/13_RUNBOOK_REINSTALLATION.md) |

Portail complet : [`docs/README.md`](docs/README.md).

## Quick start — parcours canonique

> **Important :** le premier enrôlement de l'identité physique des SSD demande un contrôle humain. Ne remplacez jamais une baseline uniquement pour faire disparaître une alerte.

### 1. Observer la machine

```powershell
.\install.ps1 -Mode Audit
```

### 2. Enrôler l'identité du stockage lors de la première qualification

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Audit
.\scripts\bootstrap\00_storage_identity_v25.ps1 `
  -Mode Record `
  -ConfirmHealthyTopology
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Verify
```

Avant `Record`, vérifiez que `C:` est bien le volume Windows attendu et que `E:` est le second SSD NTFS destiné aux données et à WSL2. Si la baseline existe déjà, utilisez uniquement `-Mode Verify`.

Guide de sécurité : [`docs/25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](docs/25_IDENTITE_STOCKAGE_ET_RECUPERATION.md).

### 3. Prévisualiser les changements

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

### 4. Faire converger

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

### 5. Vérifier la conformité

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

### 6. Prouver l'idempotence

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Une machine stabilisée doit tendre vers `DÉJÀ OK` au lieu de reproposer les mêmes mutations.

Le parcours détaillé, avec critères de succès et conditions d'arrêt, est [`docs/20_RUNBOOK_OPERATIONNEL.md`](docs/20_RUNBOOK_OPERATIONNEL.md).

## Comprendre les modes

| Mode / option | Question à laquelle il répond |
| --- | --- |
| `Audit` | Quel est l'état réel de la machine ? |
| `PlanOnly` | Qu'est-ce qui serait modifié ? |
| `Apply` | Quels écarts doivent être corrigés ? |
| `Verify` | L'état final respecte-t-il les contrats ? |
| `Rollback` | Quels réglages gérés peuvent revenir à leur état enregistré ? |
| `FullInstall` | Quel parcours global Windows + WSL2 + DevOps doit être convergé ? |

`-FullInstall` active notamment `InstallDevOps`, `ValidateDevOps`, `ValidateWsl` et `ValidateHardware`. Il ne déclenche aucun projet externe.

## Quand la workstation est-elle prête ?

Le résultat final doit combiner :

```text
Windows qualifié
+ matériel qualifié
+ identité du stockage vérifiée
+ WSL2 conforme
+ stack DevOps conforme
+ Windows Terminal conforme
+ idempotence démontrée
+ preuves exploitables
+ sauvegarde vérifiée
+ absence de dérive inexpliquée
```

Checklist officielle : [`docs/24_CRITERES_ACCEPTATION.md`](docs/24_CRITERES_ACCEPTATION.md).

## Sécurité et garde-fous

Le projet privilégie la convergence contrôlée :

- Defender, firewall et Windows Update restent des composants normaux de la workstation ;
- les versions sensibles viennent des contrats du dépôt, pas d'un `latest` arbitraire ;
- les preuves non observables automatiquement restent explicitement humaines ;
- `C:` et `E:` sont identifiés physiquement avant les parcours stricts ;
- le dépôt ne formate pas automatiquement un disque pour résoudre une ambiguïté ;
- une CI verte ne remplace pas une preuve `PHYSICAL` sur la workstation réelle ;
- la reconstruction après incident est séparée de l'exploitation quotidienne.

## Organisation du dépôt

```text
Windows_11_Pro_Custom/
├── README.md
├── START_MENU.cmd
├── menu.ps1
├── install.ps1
├── update.ps1
├── config/        # sources de vérité déclaratives
├── manifests/     # catalogues versionnés
├── scripts/       # implémentation
├── docs/          # guides, références et runbooks
├── tests/         # validations lorsqu'elles existent
├── logs/          # sorties d'exécution
├── reports/       # rapports structurés
└── .github/workflows/
```

`logs/` et `reports/` contiennent des preuves produites à l'exécution ; ils ne remplacent pas les contrats versionnés.

## Documentation

La documentation a des rôles distincts :

- **README** : présenter le projet et orienter ;
- **guide de prise en main** : expliquer les concepts ;
- **documentation technique** : définir l'architecture et les contrats ;
- **runbooks** : exécuter une procédure dans un ordre vérifiable ;
- **référence** : fournir commandes, paramètres et valeurs exactes ;
- **troubleshooting** : diagnostiquer par symptôme et domaine ;
- **critères d'acceptation** : décider si le résultat est réellement terminé.

Commencez par [`docs/README.md`](docs/README.md).

En cas de divergence entre texte, scripts, configuration et état observé, utilisez [`docs/23_SOURCES_DE_VERITE.md`](docs/23_SOURCES_DE_VERITE.md). La documentation active décrit **l'état courant** ; `CHANGELOG.md` et Git conservent l'historique.
