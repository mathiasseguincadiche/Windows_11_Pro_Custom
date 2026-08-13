# Documentation officielle — Windows 11 Pro Custom

Ce dossier contient la **documentation technique officielle** de `Windows_11_Pro_Custom`.

Le [`README.md`](../README.md) racine est la vitrine : il explique rapidement ce qu'est le projet, pourquoi il existe, son architecture et comment commencer.

Le dossier `docs/` va plus loin : il explique **comment construire la workstation, pourquoi chaque choix existe, comment l'exploiter, comment la valider, comment la maintenir et comment la reconstruire**.

> La documentation active décrit l'état actuel du projet. L'historique des évolutions appartient à [`CHANGELOG.md`](../CHANGELOG.md) et à Git.

---

## Comment utiliser cette documentation

Il existe plusieurs parcours selon ton objectif.

### Je découvre le projet

Lire :

```text
README racine
   ↓
00_ARCHITECTURE
   ↓
18_GUIDE_MAITRE
```

Tu comprendras ce que construit la workstation, les frontières Windows/WSL2, le stockage, la stack DevOps, l'orchestration, la sécurité et la reprise.

### Je veux réaliser le projet de A à Z

Lire et suivre :

1. [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) — ordre officiel des opérations ;
2. [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) — paramètres et commandes ;
3. [`11_VALIDATION.md`](11_VALIDATION.md) — preuves de conformité ;
4. [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md) — checklist finale.

C'est le **parcours opérationnel principal**.

### Je pars d'un Windows vierge

1. [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) ;
2. [`02_BIOS_DRIVERS.md`](02_BIOS_DRIVERS.md) ;
3. [`03_STOCKAGE.md`](03_STOCKAGE.md) ;
4. [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).

L'installation de Windows prépare le terrain. La réalisation du projet commence ensuite par l'audit, le plan, la convergence et la validation.

### Je reconstruis après une panne

Utiliser :

1. [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) ;
2. [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md).

Le Runbook de réinstallation est volontairement séparé du Runbook opérationnel : **reconstruire après incident n'est pas la même chose que réaliser normalement le projet**.

### Je veux apprendre WSL2

1. [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md) — cours pédagogique ;
2. [`06_WSL2.md`](06_WSL2.md) — contrat réel de cette workstation ;
3. [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md) — environnement DevOps.

### Quelque chose ne fonctionne pas

Commencer par [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md), puis utiliser [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md) pour identifier le contrat qui fait autorité.

---

# Carte du projet

```text
MATÉRIEL
   ↓
Windows 11 Pro
   ├── applications / pilotes / sécurité
   ├── PowerShell 7 / VS Code / WezTerm
   ├── Windows Update / WinGet
   ├── sauvegarde Windows
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

La règle structurante reste :

```text
Windows gère l'expérience Windows
Linux gère les workloads Linux
```

Les projets DevOps Linux vivent sous `~/projects`, `~/labs` ou `~/repositories` sur le filesystem ext4 de WSL2.

---

# Documentation par responsabilité

## 00 — Architecture

[`00_ARCHITECTURE.md`](00_ARCHITECTURE.md)

Explique :

- l'identité du projet ;
- l'architecture logique ;
- Windows vs WSL2 ;
- les deux SSD ;
- la place d'OpenClaw ;
- les frontières de responsabilité.

À lire avant toute modification structurante.

## 01 — Installation Windows

[`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md)

Guide depuis un PC à installer jusqu'à une base Windows 11 Pro exploitable.

Il couvre le média d'installation, l'UEFI, le stockage, les pilotes, Windows Update, la récupération du dépôt et le passage vers l'orchestration.

## 02 — BIOS et pilotes

[`02_BIOS_DRIVERS.md`](02_BIOS_DRIVERS.md)

Explique les attentes UEFI, Secure Boot, TPM, virtualisation, ReBAR et la stratégie de pilotes AMD / Intel / MSI.

Le dépôt qualifie ces éléments sans les modifier aveuglément.

## 03 — Stockage

[`03_STOCKAGE.md`](03_STOCKAGE.md)

Explique :

```text
C: -> Windows
D: -> données + WSL2 + intégrations lourdes
```

et pourquoi Ubuntu utilise ext4 **dans son VHDX** sans nécessiter de partition EXT4 physique.

## 04 — Optimisation Windows

[`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md)

Décrit les profils gérés, les mesures avant/après, les limites de sécurité et le rollback possible.

L'objectif est la réactivité, pas un debloat destructif.

## 05 — Defender et performances

[`05_DEFENDER_PERFORMANCE.md`](05_DEFENDER_PERFORMANCE.md)

Explique la politique d'exclusions deny-by-default et la méthode de mesure avant toute exception.

## 06 — WSL2

[`06_WSL2.md`](06_WSL2.md)

Référence de la configuration WSL2 réelle : Ubuntu 26.04, stockage sous `D:\WSL\Ubuntu-DevOps`, profils de ressources, réseau, systemd et filesystem.

## 07 — Stack DevOps

[`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md)

Explique Docker, Kubernetes, Terraform, Ansible, AWS, GitHub CLI, les outils qualité, le terminal Bash et VS Code WSL.

## 08 — Applications Windows

[`08_APPLICATIONS.md`](08_APPLICATIONS.md)

Catalogue applicatif, automatisation WinGet et logiciels volontairement laissés manuels quand l'installation n'est pas assez fiable.

## 09 — Gaming et affichage

[`09_GAMING_OLED.md`](09_GAMING_OLED.md)

Explique les choix liés à l'usage gaming/affichage sans mélanger cette couche avec le backend DevOps.

## 10 — Backup et restore

[`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md)

Décrit la stratégie de protection de `C:`, `D:`, Ubuntu WSL2 et la préparation d'une reprise après incident.

La sauvegarde est une partie du projet, pas une tâche annexe.

## 11 — Validation

[`11_VALIDATION.md`](11_VALIDATION.md)

Explique comment passer de « le script s'est exécuté » à « la machine est réellement conforme ».

C'est le document de référence pour les preuves, les validateurs et les verdicts.

## 12 — Qualification matérielle

[`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md)

Distingue les contrôles automatisables des preuves physiques/firmware qui restent manuelles.

## 13 — Runbook de réinstallation

[`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md)

Procédure de reconstruction après panne, remplacement de disque ou réinstallation complète.

**Ce n'est pas le Runbook normal de réalisation du projet.** Pour le parcours quotidien de construction et validation, utiliser `20_RUNBOOK_OPERATIONNEL.md`.

## 14 — Orchestration

[`14_ORCHESTRATION.md`](14_ORCHESTRATION.md)

Explique machine-first, Verify avant Apply, plan factuel, idempotence, re-vérification, logs, actions humaines et rollback géré.

## 15 — Mises à jour

[`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md)

Explique la maintenance séparée de Windows Update, WinGet, WSL, Ubuntu/APT, outils DevOps épinglés et extensions VS Code.

## 16 — Guide WSL2 complet

[`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md)

Cours progressif pour apprendre WSL2, Linux, filesystems, systemd, réseau, Docker et les commandes utiles à cette workstation.

## 17 — Centre de contrôle

[`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md)

Explique `START_MENU.cmd` et `menu.ps1`, leur rôle d'interface et le routage vers les vrais orchestrateurs.

## 18 — Guide maître

[`18_GUIDE_MAITRE.md`](18_GUIDE_MAITRE.md)

Vision consolidée de l'ensemble du projet.

## 19 — OpenClaw / OpenRouter Windows

[`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md)

Explique l'intégration IA optionnelle sous `D:\AI\OpenClaw` et sa relation avec le backend DevOps WSL2.

## 20 — Runbook opérationnel

[`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md)

**Parcours officiel pour réaliser le projet de A à Z** : audit, plan, convergence, WSL2, DevOps, matériel, validation, idempotence et sauvegarde.

## 21 — Référence des commandes

[`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md)

Décrit `menu.ps1`, `install.ps1`, `update.ps1`, leurs modes, options et résultats attendus.

## 22 — Troubleshooting

[`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md)

Méthode de diagnostic et incidents courants : WSL2, stockage, utilisateur Linux, DevOps, matériel, Defender, maintenance, OpenClaw et CI.

## 23 — Sources de vérité

[`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md)

Explique la hiérarchie entre machine réelle, `config/`, `manifests/`, scripts, `Verify`, logs, rapports, documentation et historique Git.

## 24 — Critères d'acceptation

[`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md)

Checklist finale pour décider objectivement si la workstation est réellement prête.

---

# Parcours opérationnel résumé

```powershell
# 1. Observer l'état réel
.\install.ps1 -Mode Audit

# 2. Prévisualiser la convergence complète
.\install.ps1 -Mode Apply -FullInstall -PlanOnly

# 3. Faire converger
.\install.ps1 -Mode Apply -FullInstall

# 4. Valider les domaines principaux
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps

# 5. Contrôler la maintenance
.\update.ps1 -Mode Audit

# 6. Recalculer le plan pour prouver l'idempotence
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Les détails, précautions et actions humaines se trouvent dans [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).

---

# Sources de vérité

Le modèle à retenir est :

```text
machine réelle
   +
configurations / manifests
   ↓
scripts / validateurs
   ↓
Verify
   ↓
logs / rapports
   ↓
documentation explicative
```

Les fichiers `state/` servent au rollback de certains composants et ne deviennent pas une preuve de conformité actuelle.

En cas de divergence, suivre [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

---

# Ce que la documentation active ne doit pas faire

Elle ne doit pas :

- obliger un débutant à comprendre l'historique avant l'état actuel ;
- dupliquer des anciens guides versionnés ;
- documenter des commandes inexistantes ;
- promettre une automatisation que le code ne fournit pas ;
- masquer une action humaine obligatoire ;
- confondre une CI verte avec la qualification physique de la workstation ;
- confondre réalisation normale et disaster recovery.

Le principe est :

```text
README / docs = présent
CHANGELOG     = historique
Git           = détail complet des évolutions
```

---

## Point de départ recommandé

Si tu veux **comprendre**, commence par [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md).

Si tu veux **réaliser le projet**, commence par [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).

Si tu veux **prouver qu'il est terminé**, utilise [`11_VALIDATION.md`](11_VALIDATION.md) puis [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md).