# Documentation — Windows 11 Pro Custom

Ce dossier contient la documentation actuelle de **Windows 11 Pro Custom**.

Le projet décrit une workstation Windows 11 Pro personnelle, reproductible et orientée **DevOps/Ops**, capable de rester performante pour les usages desktop/gaming tout en fournissant un backend Linux complet via WSL2.

La documentation est organisée par **responsabilité fonctionnelle**, pas par ancienne version du projet.

> Les numéros de version et l'historique des évolutions appartiennent à [`../CHANGELOG.md`](../CHANGELOG.md). Les guides ci-dessous décrivent uniquement **l'état actuel de la workstation**.

---

## Comprendre le projet en quelques minutes

Lire dans cet ordre :

1. [`../README.md`](../README.md) — ce qu'est la workstation et pourquoi elle existe ;
2. [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) — comment Windows, WSL2, les SSD et les outils sont séparés ;
3. [`18_GUIDE_MAITRE.md`](18_GUIDE_MAITRE.md) — vision complète et exploitation du projet.

Le modèle mental est :

```text
matériel cible
   ↓
Windows 11 Pro
   ├── desktop / gaming / drivers / sécurité
   ├── PowerShell / VS Code / WezTerm
   ├── mises à jour / sauvegarde
   └── WSL2
       └── Ubuntu 26.04
           ├── Bash
           ├── Docker / Kubernetes
           ├── Terraform / Ansible
           ├── AWS / GitHub CLI
           └── outils qualité
```

Windows reste l'hôte. WSL2 fournit le backend Linux DevOps.

---

## Quel document lire ?

| Besoin | Document |
| --- | --- |
| Comprendre le projet | [`18_GUIDE_MAITRE.md`](18_GUIDE_MAITRE.md) |
| Comprendre l'architecture | [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) |
| Installer Windows depuis zéro | [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) |
| Vérifier BIOS / pilotes | [`02_BIOS_DRIVERS.md`](02_BIOS_DRIVERS.md) |
| Comprendre les deux SSD | [`03_STOCKAGE.md`](03_STOCKAGE.md) |
| Comprendre les optimisations Windows | [`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md) |
| Comprendre Defender et les performances | [`05_DEFENDER_PERFORMANCE.md`](05_DEFENDER_PERFORMANCE.md) |
| Configurer et exploiter WSL2 | [`06_WSL2.md`](06_WSL2.md) |
| Comprendre la stack DevOps | [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md) |
| Voir les applications Windows | [`08_APPLICATIONS.md`](08_APPLICATIONS.md) |
| Gaming / affichage | [`09_GAMING_OLED.md`](09_GAMING_OLED.md) |
| Sauvegarder et restaurer | [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) |
| Vérifier que la machine est conforme | [`11_VALIDATION.md`](11_VALIDATION.md) |
| Qualifier le matériel | [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md) |
| Reconstruire toute la machine | [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) |
| Comprendre la convergence | [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) |
| Gérer les mises à jour | [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md) |
| Apprendre WSL2 depuis zéro | [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md) |
| Utiliser le menu interactif | [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md) |
| Intégrer OpenClaw/OpenRouter | [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md) |

---

## Parcours 1 — Je découvre le dépôt

Commence par comprendre **ce que la workstation cherche à obtenir**, avant de lancer un script.

```text
README racine
   ↓
00_ARCHITECTURE
   ↓
18_GUIDE_MAITRE
   ↓
document du composant qui t'intéresse
```

À retenir :

- `C:` contient Windows et les applications ;
- `D:` contient les données, WSL2 et les intégrations lourdes ;
- WSL2 possède son filesystem ext4 dans un VHDX ;
- les projets Linux restent dans `/home/<user>/...` ;
- Windows et Linux ont des responsabilités distinctes ;
- les réglages gérés doivent être vérifiables et réversibles lorsque c'est possible ;
- une vraie sauvegarde est distincte du dépôt Git.

---

## Parcours 2 — J'installe la workstation depuis zéro

Suivre :

1. [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) ;
2. [`02_BIOS_DRIVERS.md`](02_BIOS_DRIVERS.md) ;
3. [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md) ;
4. [`11_VALIDATION.md`](11_VALIDATION.md) ;
5. [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

Le guide d'installation couvre la préparation de Windows, les pilotes, le stockage et la récupération du dépôt.

Une fois la base disponible, le centre de contrôle peut guider les opérations automatisées :

```text
START_MENU.cmd
```

ou :

```powershell
.\menu.ps1
```

Le menu est une interface ; la logique reste dans les orchestrateurs documentés dans [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md).

---

## Parcours 3 — Je veux apprendre WSL2 correctement

Lire :

1. [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md) — cours débutant → avancé ;
2. [`06_WSL2.md`](06_WSL2.md) — configuration actuelle de cette machine ;
3. [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md) — outils DevOps et terminal.

Règle fondamentale :

```text
Projet Linux / DevOps
        ↓
/home/<user>/projects
```

`/mnt/c` et `/mnt/d` restent des ponts vers Windows, pas les racines de travail principales pour Docker, Terraform, Ansible ou des builds Linux.

---

## Parcours 4 — Je veux exploiter la machine au quotidien

Les points d'entrée humains principaux sont :

```text
menu.ps1    -> choisir une action
install.ps1 -> audit / convergence / validation
update.ps1  -> maintenance
```

Lire :

- [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md) ;
- [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) ;
- [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md) ;
- [`11_VALIDATION.md`](11_VALIDATION.md).

---

## Parcours 5 — Je prépare une sauvegarde ou une reprise

Lire :

1. [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) ;
2. [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md).

La stratégie distingue :

```text
GitHub
   -> protège le socle versionné

System Restore
   -> rollback Windows léger

Image Windows
   -> protège C: + D: + volumes critiques

Export WSL VHDX
   -> protège Ubuntu indépendamment
```

La restauration bare-metal reste volontairement manuelle.

---

## Documentation complète

### 00 — Architecture

[`00_ARCHITECTURE.md`](00_ARCHITECTURE.md)

Explique :

- architecture logique Windows/WSL2 ;
- stockage physique ;
- frontières de responsabilité ;
- terminal, VS Code et OpenClaw ;
- organisation du dépôt.

### 01 — Installation Windows

[`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md)

Procédure depuis un PC à installer jusqu'à une base Windows exploitable.

### 02 — BIOS et pilotes

[`02_BIOS_DRIVERS.md`](02_BIOS_DRIVERS.md)

UEFI, Secure Boot, TPM, virtualisation, ReBAR et stratégie de drivers.

### 03 — Stockage

[`03_STOCKAGE.md`](03_STOCKAGE.md)

Organisation `C:` / `D:`, WSL2, VHDX, TRIM et règles de placement.

### 04 — Optimisation Windows

[`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md)

Réactivité, confidentialité, gaming, mesures avant/après et limites de sécurité.

### 05 — Defender

[`05_DEFENDER_PERFORMANCE.md`](05_DEFENDER_PERFORMANCE.md)

Mesure de performance et politique d'exclusions deny-by-default.

### 06 — WSL2

[`06_WSL2.md`](06_WSL2.md)

Contrat Ubuntu, profils de ressources, réseau, stockage et exploitation.

### 07 — Stack DevOps

[`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md)

Docker, Kubernetes, Terraform, Ansible, AWS, terminal Bash et VS Code WSL.

### 08 — Applications

[`08_APPLICATIONS.md`](08_APPLICATIONS.md)

Socle WinGet et logiciels conservés manuels.

### 09 — Gaming / affichage

[`09_GAMING_OLED.md`](09_GAMING_OLED.md)

Choix liés au gaming et à l'affichage.

### 10 — Backup / restore

[`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md)

Protection de Windows, `D:`, WSL2 et reconstruction.

### 11 — Validation

[`11_VALIDATION.md`](11_VALIDATION.md)

Comment prouver qu'un composant est réellement prêt.

### 12 — Qualification matérielle

[`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md)

Contrôles automatiques et preuves manuelles du matériel réel.

### 13 — Runbook de réinstallation

[`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md)

Procédure opérationnelle complète de reconstruction.

### 14 — Orchestration

[`14_ORCHESTRATION.md`](14_ORCHESTRATION.md)

Machine-first, plan, idempotence, Apply ciblé, Verify et logs.

### 15 — Mises à jour

[`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md)

Windows Update, WinGet, WSL, Ubuntu, DevOps épinglé et VS Code.

### 16 — Guide WSL2 complet

[`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md)

Guide pédagogique pour apprendre WSL2 depuis zéro.

### 17 — Centre de contrôle

[`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md)

Utilisation de `menu.ps1` et routage vers les orchestrateurs.

### 18 — Guide maître

[`18_GUIDE_MAITRE.md`](18_GUIDE_MAITRE.md)

Vision consolidée de toute la workstation.

### 19 — OpenClaw / OpenRouter

[`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md)

Intégration de la plateforme IA dans l'architecture Windows.

---

## Ce que la documentation ne doit plus faire

La documentation active ne doit plus être structurée comme :

```text
ancienne couche A
ancienne couche B
ancienne couche C
...
```

Ce modèle raconte l'histoire du dépôt mais oblige un lecteur à comprendre le passé avant de comprendre le présent.

Le principe actuel est :

```text
README/docs = état actuel
CHANGELOG   = historique
Git         = détail complet des évolutions
```

---

## Source de vérité

En cas de divergence :

1. état réel de la machine ;
2. configurations et manifests actuels ;
3. scripts actuels ;
4. documentation actuelle ;
5. changelog / historique Git.

Pour Windows, BIOS et drivers qui évoluent avec le temps, la source officielle du constructeur ou de Microsoft doit toujours être vérifiée avant une installation réelle.
