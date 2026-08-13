# Windows 11 Pro Custom — workstation DevOps/Ops reproductible

[![Qualité](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/quality.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/quality.yml)
[![Runtime WSL](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/wsl-runtime-contract.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/wsl-runtime-contract.yml)
[![Documentation](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/documentation.yml/badge.svg)](https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom/actions/workflows/documentation.yml)

`Windows_11_Pro_Custom` est le projet qui définit, automatise, vérifie et documente **ma workstation Windows 11 Pro de référence** pour un usage **DevOps/Ops**, administration système, Linux via WSL2, desktop quotidien et gaming.

Ce dépôt n'est pas une collection de tweaks Windows ni un simple script d'installation. Il transforme la configuration de la machine en un **projet reproductible** : les choix importants sont versionnés, l'état réel est observé avant modification, les écarts sont corrigés de manière ciblée, le résultat est re-vérifié et la reprise après incident est prévue.

> **Objectif du projet :** pouvoir partir d'un Windows propre ou d'une machine déjà utilisée, retrouver la même architecture, les mêmes outils et les mêmes garde-fous, comprendre ce qui est déjà conforme, corriger uniquement ce qui manque, valider le résultat puis conserver une sauvegarde de référence exploitable.

Si tu découvres le dépôt, ce README doit te permettre de répondre immédiatement à cinq questions :

1. **Qu'est-ce que ce projet construit ?**
2. **Pourquoi l'architecture est-elle organisée ainsi ?**
3. **Comment le projet agit-il sur la machine ?**
4. **Dans quel ordre faut-il l'exécuter ?**
5. **Comment savoir que le résultat final est réellement valide ?**

La documentation détaillée se trouve dans [`docs/`](docs/README.md).

---

## 1. Ce que construit réellement le projet

Le résultat final est une workstation cohérente qui combine plusieurs usages sans mélanger leurs responsabilités :

```text
                         MATÉRIEL CIBLE
                              │
                              ▼
                        Windows 11 Pro
               ┌──────────────┼──────────────┐
               │              │              │
               ▼              ▼              ▼
         Desktop/gaming   Administration   WSL2 / Ubuntu
         applications     PowerShell 7          │
         pilotes          sécurité              ▼
         VS Code UI       maintenance       Linux DevOps
         WezTerm          sauvegarde        Docker / K8s
               │                           Terraform
               │                           Ansible / AWS
               └──────────────┬──────────────┘
                              ▼
                     workstation cohérente
                              │
                  audit → plan → convergence
                              │
                              ▼
                    validation → sauvegarde
```

Le dépôt couvre ou documente notamment :

- Windows 11 Pro et son organisation ;
- le matériel cible et sa qualification ;
- les deux SSD et leur rôle ;
- PowerShell 7, VS Code, WezTerm et OpenSSH Client ;
- les applications Windows gérées ;
- WSL2 avec Ubuntu 26.04 ;
- Docker, Kubernetes, Terraform, Ansible, AWS CLI et outils qualité ;
- les réglages Windows maîtrisés et mesurables ;
- Microsoft Defender et les limites d'exclusion ;
- les mises à jour de la workstation ;
- l'audit, les logs, les rapports et la validation ;
- la sauvegarde Windows + WSL2 et le plan de reprise ;
- l'intégration optionnelle d'OpenClaw/OpenRouter sous `D:\AI\OpenClaw`.

Les scripts sont le **moyen** d'obtenir cette workstation. Le projet, lui, est l'ensemble cohérent formé par l'architecture, les contrats, l'automatisation, la validation, la documentation et la reprise.

---

## 2. Le principe central : une workstation-as-code

Le dépôt applique à une machine personnelle des principes proches de l'Infrastructure as Code :

```text
état attendu versionné
        +
état réel observé
        ↓
comparaison
        ↓
plan factuel
        ↓
action minimale
        ↓
re-vérification
        ↓
preuve / rapport / verdict
```

### Machine-first

La machine réelle est inspectée avant de décider qu'une action est nécessaire.

### Idempotence

Un composant déjà conforme doit être signalé comme `DÉJÀ OK` et ne pas être réinstallé inutilement.

### Réversibilité

Lorsqu'un état initial fiable peut être capturé, les réglages gérés peuvent disposer d'un rollback.

### Sécurité conservée

La performance ne justifie pas de désactiver Defender, Windows Update, le firewall, Secure Boot, TPM, WSL ou d'autres briques nécessaires au système.

### Matériel-aware

Le dépôt connaît la machine cible et valide son état au lieu d'appliquer des valeurs génériques prévues pour n'importe quel PC.

### Recovery-first

Une workstation bien configurée mais impossible à restaurer n'est pas considérée comme totalement terminée.

Ces principes sont implémentés dans `install.ps1`, `scripts/core/` et les validateurs spécialisés. Le détail est dans [`docs/14_ORCHESTRATION.md`](docs/14_ORCHESTRATION.md).

---

## 3. Architecture de la machine cible

### Matériel

| Composant | Cible |
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

Le dépôt **qualifie** ce matériel. Il ne modifie pas automatiquement les réglages firmware ou d'overclocking qui nécessitent une décision humaine.

Documentation : [`docs/12_HARDWARE_QUALIFICATION.md`](docs/12_HARDWARE_QUALIFICATION.md).

### Stockage

```text
Crucial T705 #1
└── C: NTFS
    ├── Windows 11 Pro
    ├── applications
    ├── pilotes
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

Il n'y a ni dual boot ni partition EXT4 physique prévue par le projet. Ubuntu possède bien un filesystem Linux ext4, mais il se trouve **dans son VHDX WSL2** stocké sur le second SSD NTFS.

Documentation : [`docs/03_STOCKAGE.md`](docs/03_STOCKAGE.md).

---

## 4. Windows reste l'hôte, WSL2 devient le backend Linux

La séparation des responsabilités est volontaire.

### Windows 11 Pro gère

- l'interface graphique ;
- les pilotes et périphériques ;
- les navigateurs et applications desktop ;
- Steam et le gaming ;
- PowerShell 7 ;
- VS Code côté interface ;
- WezTerm ;
- Windows Update et WinGet ;
- Microsoft Defender ;
- le runtime WSL ;
- les sauvegardes Windows ;
- OpenClaw Windows lorsque cette intégration est utilisée.

### Ubuntu WSL2 gère

- Bash ;
- Git pour les projets Linux ;
- Docker Engine, Compose et Buildx ;
- kubectl et Helm ;
- Minikube et kind ;
- Terraform ;
- Ansible ;
- AWS CLI ;
- GitHub CLI ;
- Trivy ;
- les outils qualité shell/IaC.

La règle opérationnelle est :

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

Documentation : [`docs/06_WSL2.md`](docs/06_WSL2.md) et [`docs/07_DEVOPS_STACK.md`](docs/07_DEVOPS_STACK.md).

---

## 5. Profil WSL2 de référence

Le profil quotidien est dimensionné pour garder une vraie réserve à Windows :

```text
Ubuntu 26.04
20 Go RAM
8 threads
8 Go swap
réseau mirrored
DNS tunneling
firewall actif
autoMemoryReclaim progressif
```

Le projet fournit aussi un profil plus lourd pour certains labs et un profil réseau de repli.

Le contrat runtime exige actuellement `Ubuntu` sous `D:\WSL\Ubuntu-DevOps`, avec le HOME et les workspaces Linux sur ext4.

Documentation détaillée :

- [`docs/06_WSL2.md`](docs/06_WSL2.md) — configuration actuelle ;
- [`docs/16_WSL2_GUIDE_COMPLET.md`](docs/16_WSL2_GUIDE_COMPLET.md) — guide pédagogique débutant → avancé.

---

## 6. Une vraie plateforme DevOps/Ops

La couche Linux ne se limite pas à « WSL installé ».

Elle fournit une stack de travail :

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

Les versions sensibles à la reproductibilité sont pilotées par le dépôt via `config/devops/tool-versions.env`. Une version `latest` disponible sur Internet ne remplace pas automatiquement la cible approuvée.

WezTerm ouvre l'environnement Linux DevOps, PowerShell 7 reste disponible pour Windows et VS Code utilise le contexte WSL lorsqu'un projet est Linux.

---

## 7. Windows optimisé sans « debloat » destructif

Le projet cherche une machine réactive et prévisible, pas un Windows amputé de briques essentielles.

Il peut gérer des réglages liés à :

- la réactivité de l'interface ;
- certaines suggestions Windows ;
- la confidentialité ;
- le gaming ;
- certains services ciblés ;
- des mesures avant/après.

Il conserve les garde-fous structurants : Defender, firewall, Windows Update, pagefile, mémoire compressée, WSL et les composants nécessaires au système.

Les exclusions Defender suivent une politique **deny-by-default**.

Documentation :

- [`docs/04_OPTIMISATION_WINDOWS.md`](docs/04_OPTIMISATION_WINDOWS.md) ;
- [`docs/05_DEFENDER_PERFORMANCE.md`](docs/05_DEFENDER_PERFORMANCE.md).

---

## 8. Comment utiliser le projet

Il existe trois points d'entrée humains/techniques :

```text
START_MENU.cmd / menu.ps1
        ↓
choisir une intention

install.ps1
        ↓
audit / plan / convergence / validation / rollback géré / backup

update.ps1
        ↓
maintenance multi-couches
```

### Première commande recommandée sur une machine existante

```powershell
.\install.ps1 -Mode Audit
```

Elle établit l'état réel avant toute modification.

### Voir ce que l'installation complète ferait

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Le plan distingue notamment `DÉJÀ OK`, `À FAIRE`, `ACTION REQUISE` et les erreurs réelles.

### Faire converger le projet

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

### Valider le résultat

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

Le fait d'avoir lancé `Apply` n'est pas une preuve suffisante. Le résultat vient de `Verify` et de l'état réellement observé.

### Parcours complet de réalisation

Le guide à suivre de A à Z est :

[`docs/20_RUNBOOK_OPERATIONNEL.md`](docs/20_RUNBOOK_OPERATIONNEL.md).

La référence détaillée des paramètres est :

[`docs/21_REFERENCE_COMMANDES.md`](docs/21_REFERENCE_COMMANDES.md).

---

## 9. Comment savoir que le projet est terminé

Le projet peut être déclaré prêt lorsque :

```text
Audit compris
+
Plan cohérent
+
Convergence réussie
+
Validation Windows
+
Qualification matérielle
+
Validation WSL2
+
Validation DevOps
+
Idempotence prouvée
+
Logs/rapports exploitables
+
Sauvegarde vérifiée
```

OpenClaw est ajouté à cette chaîne seulement si l'intégration est utilisée.

La checklist officielle est [`docs/24_CRITERES_ACCEPTATION.md`](docs/24_CRITERES_ACCEPTATION.md).

---

## 10. Sauvegarde et reprise

GitHub protège le **socle versionné**, pas la machine réelle.

La stratégie de protection distingue :

```text
System Restore
        ↓
rollback Windows léger

Image Windows
        ↓
C: + D: + volumes critiques

Export WSL VHDX + intégrité
        ↓
Ubuntu restaurable séparément

GitHub
        ↓
reconstruction du socle versionné
```

La restauration complète reste volontairement une opération humaine et contrôlée.

Documentation :

- [`docs/10_BACKUP_RESTORE.md`](docs/10_BACKUP_RESTORE.md) — stratégie de sauvegarde ;
- [`docs/13_RUNBOOK_REINSTALLATION.md`](docs/13_RUNBOOK_REINSTALLATION.md) — reconstruction après incident.

Le Runbook de réinstallation n'est **pas** le parcours normal de réalisation du projet. Pour construire et valider la workstation, utiliser le Runbook opérationnel `20`.

---

## 11. Maintenance

Les domaines de maintenance restent séparés :

```text
Windows Update
WinGet
WSL runtime
Ubuntu / APT
outils DevOps épinglés
extensions VS Code
```

Point d'entrée :

```powershell
.\update.ps1 -Mode Audit
```

Puis `Apply` et `Verify` lorsque la maintenance est nécessaire.

Drivers et mises à jour facultatives sont opt-in ; aucun changement majeur d'Ubuntu ni redémarrage n'est imposé silencieusement.

Documentation : [`docs/15_MISES_A_JOUR.md`](docs/15_MISES_A_JOUR.md).

---

## 12. OpenClaw/OpenRouter

L'intégration IA est optionnelle et isolée sous :

```text
D:\AI\OpenClaw
```

Le dépôt `Windows_11_Pro_Custom` prépare l'environnement, le stockage et la validation d'intégration. Le comportement métier d'OpenClaw/OpenRouter reste la responsabilité du dépôt dédié `openclaw_openrouter`.

Le control-plane consommé par Windows est référencé explicitement dans `config/openclaw/control-plane.json`.

Documentation : [`docs/19_OPENCLAW_OPENROUTER_WINDOWS.md`](docs/19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

## 13. Structure du dépôt

```text
Windows_11_Pro_Custom/
├── README.md
├── CHANGELOG.md
├── START_MENU.cmd
├── menu.ps1
├── install.ps1
├── update.ps1
├── config/          # contrats et politiques
├── manifests/       # catalogues déclaratifs
├── scripts/         # implémentation par responsabilité
├── docs/            # documentation technique officielle
├── logs/            # journaux d'exécution
├── reports/         # rapports et preuves structurées
└── state/           # états nécessaires à certains rollbacks
```

La carte complète des sources de vérité se trouve dans [`docs/23_SOURCES_DE_VERITE.md`](docs/23_SOURCES_DE_VERITE.md).

---

## 14. Documentation officielle

Le dossier [`docs/`](docs/README.md) est la référence technique humaine du projet.

| Besoin | Document |
| --- | --- |
| Comprendre l'architecture | [`docs/00_ARCHITECTURE.md`](docs/00_ARCHITECTURE.md) |
| Installer Windows depuis zéro | [`docs/01_INSTALLATION_WINDOWS.md`](docs/01_INSTALLATION_WINDOWS.md) |
| BIOS et pilotes | [`docs/02_BIOS_DRIVERS.md`](docs/02_BIOS_DRIVERS.md) |
| Stockage | [`docs/03_STOCKAGE.md`](docs/03_STOCKAGE.md) |
| Optimisation Windows | [`docs/04_OPTIMISATION_WINDOWS.md`](docs/04_OPTIMISATION_WINDOWS.md) |
| Defender | [`docs/05_DEFENDER_PERFORMANCE.md`](docs/05_DEFENDER_PERFORMANCE.md) |
| WSL2 | [`docs/06_WSL2.md`](docs/06_WSL2.md) |
| Stack DevOps | [`docs/07_DEVOPS_STACK.md`](docs/07_DEVOPS_STACK.md) |
| Applications | [`docs/08_APPLICATIONS.md`](docs/08_APPLICATIONS.md) |
| Gaming / affichage | [`docs/09_GAMING_OLED.md`](docs/09_GAMING_OLED.md) |
| Backup / restore | [`docs/10_BACKUP_RESTORE.md`](docs/10_BACKUP_RESTORE.md) |
| Validation | [`docs/11_VALIDATION.md`](docs/11_VALIDATION.md) |
| Qualification matérielle | [`docs/12_HARDWARE_QUALIFICATION.md`](docs/12_HARDWARE_QUALIFICATION.md) |
| Reconstruction après incident | [`docs/13_RUNBOOK_REINSTALLATION.md`](docs/13_RUNBOOK_REINSTALLATION.md) |
| Orchestration | [`docs/14_ORCHESTRATION.md`](docs/14_ORCHESTRATION.md) |
| Mises à jour | [`docs/15_MISES_A_JOUR.md`](docs/15_MISES_A_JOUR.md) |
| Apprendre WSL2 | [`docs/16_WSL2_GUIDE_COMPLET.md`](docs/16_WSL2_GUIDE_COMPLET.md) |
| Centre de contrôle | [`docs/17_CONTROL_CENTER.md`](docs/17_CONTROL_CENTER.md) |
| Guide maître | [`docs/18_GUIDE_MAITRE.md`](docs/18_GUIDE_MAITRE.md) |
| OpenClaw/OpenRouter | [`docs/19_OPENCLAW_OPENROUTER_WINDOWS.md`](docs/19_OPENCLAW_OPENROUTER_WINDOWS.md) |
| **Réaliser le projet de A à Z** | **[`docs/20_RUNBOOK_OPERATIONNEL.md`](docs/20_RUNBOOK_OPERATIONNEL.md)** |
| Référence des commandes | [`docs/21_REFERENCE_COMMANDES.md`](docs/21_REFERENCE_COMMANDES.md) |
| Troubleshooting | [`docs/22_TROUBLESHOOTING.md`](docs/22_TROUBLESHOOTING.md) |
| Sources de vérité | [`docs/23_SOURCES_DE_VERITE.md`](docs/23_SOURCES_DE_VERITE.md) |
| Critères d'acceptation | [`docs/24_CRITERES_ACCEPTATION.md`](docs/24_CRITERES_ACCEPTATION.md) |

---

## 15. Si quelque chose ne fonctionne pas

Commence par :

1. identifier le composant ;
2. lire son log ;
3. vérifier le contrat correspondant ;
4. corriger la cause ;
5. relancer le même `Verify` ou l'`Apply` ciblé.

Ne contourne pas un validateur en affaiblissant la sécurité du système.

Guide : [`docs/22_TROUBLESHOOTING.md`](docs/22_TROUBLESHOOTING.md).

---

## 16. Source de vérité et historique

La documentation active décrit **l'état actuel du projet**.

```text
README / docs -> présent et exploitation
CHANGELOG     -> historique fonctionnel
Git           -> détail des évolutions
```

Les noms de certains fichiers internes peuvent conserver un identifiant technique historique lorsqu'il fait partie du contrat actuel. Cela ne signifie pas que le lecteur doit connaître les anciennes étapes du dépôt pour utiliser la workstation aujourd'hui.

En cas de divergence, se référer à [`docs/23_SOURCES_DE_VERITE.md`](docs/23_SOURCES_DE_VERITE.md).

---

## Résumé en une phrase

**`Windows_11_Pro_Custom` transforme une workstation Windows 11 Pro personnelle en une plateforme DevOps/Ops versionnée, machine-first, reproductible, vérifiable, maintenable et récupérable, avec Windows comme hôte et Ubuntu WSL2 comme backend Linux spécialisé.**