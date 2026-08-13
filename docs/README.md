# Documentation — Windows 11 Pro Custom

Ce dossier contient la documentation officielle du projet **Windows 11 Pro Custom**.

Le projet ne se limite pas à installer quelques applications : il décrit et automatise la reconstruction d'une workstation Windows 11 Pro orientée **DevOps/Ops**, avec WSL2, Ubuntu, Docker, Kubernetes, Terraform, Ansible, VS Code, WezTerm, sauvegarde/reprise, mises à jour et qualification matérielle.

> **Si tu débutes : ne lis pas tous les fichiers dans l'ordre numérique.** Utilise le parcours ci-dessous.

---

## 1. Quel document lire ?

| Besoin | Document recommandé |
|---|---|
| Comprendre le projet en 10 minutes | [`../README.md`](../README.md) |
| Installer Windows 11 proprement depuis zéro | [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) |
| Reconstruire toute la machine après panne/réinstallation | [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) |
| Comprendre toute l'architecture et toutes les versions | [`24_GUIDE_MAITRE_V13.md`](24_GUIDE_MAITRE_V13.md) |
| Comprendre Windows vs WSL2 | [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) |
| Apprendre WSL2 depuis zéro | [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md) |
| Comprendre le tuning WSL2 de cette machine | [`17_WSL2_TUNING_V6.md`](17_WSL2_TUNING_V6.md) |
| Sauvegarder/restaurer la workstation | [`18_BACKUP_DISASTER_RECOVERY_V7.md`](18_BACKUP_DISASTER_RECOVERY_V7.md) |
| Comprendre WezTerm/Bash/VS Code | [`21_DEVOPS_TERMINAL_V10.md`](21_DEVOPS_TERMINAL_V10.md) |
| Gérer les mises à jour | [`22_SYSTEM_UPDATE_MANAGER_V11.md`](22_SYSTEM_UPDATE_MANAGER_V11.md) |
| Utiliser le menu interactif | [`23_INTERACTIVE_CONTROL_CENTER_V12.md`](23_INTERACTIVE_CONTROL_CENTER_V12.md) |

---

## 2. Parcours débutant recommandé

### Étape A — avant de toucher au PC

Lis :

1. [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) ;
2. [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) ;
3. [`02_BIOS_DRIVERS.md`](02_BIOS_DRIVERS.md).

Tu dois comprendre avant de commencer :

```text
Crucial T705 #1 -> C: -> Windows 11 Pro
Crucial T705 #2 -> D: -> données + WSL + OpenClaw
Disque USB séparé -> sauvegardes V7
```

Le second SSD reste **NTFS**. Ubuntu WSL2 possède son filesystem Linux EXT4 **dans un VHDX**, pas dans une partition EXT4 physique.

### Étape B — installer Windows 11

Suis exactement :

[`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md)

Le guide couvre :

- préparation de la clé USB ;
- réglages UEFI/BIOS ;
- identification du bon SSD ;
- installation Windows 11 Pro ;
- premier démarrage ;
- Windows Update ;
- pilotes AMD/Intel/MSI ;
- création de `D:` ;
- contrôles Secure Boot/TPM/virtualisation ;
- récupération du dépôt.

### Étape C — lancer le projet

Le point d'entrée humain principal est :

```text
START_MENU.cmd
```

ou :

```powershell
.\menu.ps1
```

Le menu permet ensuite de choisir :

```text
1. Installation complète
2. Installation / réparation des logiciels
3. Mises à jour complètes
4. Sauvegarde
5. Restauration / rollback
6. Audit et diagnostic complet
7. Vérification de conformité
8. Composants spécifiques
9. Journaux et rapports
10. Aide
```

### Étape D — apprendre WSL2

Pour ne pas utiliser WSL2 « au hasard », lis :

[`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md)

Puis la configuration spécifique de cette machine :

[`17_WSL2_TUNING_V6.md`](17_WSL2_TUNING_V6.md)

Règle fondamentale :

```text
Projet Linux/DevOps -> /home/<user>/projects
```

Évite de travailler activement depuis `/mnt/c` et `/mnt/d` avec les outils Linux.

### Étape E — valider la machine

Après installation :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware -ValidateWsl -ValidateDevOps
```

Si OpenClaw est installé :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware -ValidateWsl -ValidateDevOps -ValidateOpenClawAI
```

### Étape F — créer la sauvegarde de référence

Après avoir réellement validé la workstation :

[`18_BACKUP_DISASTER_RECOVERY_V7.md`](18_BACKUP_DISASTER_RECOVERY_V7.md)

La sauvegarde V7 est destinée à un **disque USB NTFS séparé**, pas au SSD `D:` interne.

---

## 3. Documents fondamentaux

Ces documents expliquent les concepts durables du projet.

| Fichier | Sujet |
|---|---|
| `00_ARCHITECTURE.md` | Architecture Windows/WSL/stockage, frontières et responsabilités |
| `01_INSTALLATION_WINDOWS.md` | Installation propre de Windows 11 Pro depuis zéro |
| `02_BIOS_DRIVERS.md` | UEFI, Secure Boot, TPM, SVM, ReBAR et stratégie de pilotes |
| `03_STOCKAGE.md` | Organisation des SSD et règles de stockage |
| `04_OPTIMISATION_WINDOWS.md` | Principes d'optimisation Windows |
| `05_DEFENDER_PERFORMANCE.md` | Defender, performance et exclusions mesurées |
| `06_WSL2.md` | Configuration WSL2 de référence |
| `07_DEVOPS_STACK.md` | Stack Linux DevOps |
| `08_APPLICATIONS.md` | Applications Windows |
| `09_GAMING_OLED.md` | Écran/gaming |
| `10_BACKUP_RESTORE.md` | Vue courte sauvegarde/reprise |
| `11_VALIDATION.md` | Validation et critères de conformité |
| `13_RUNBOOK_REINSTALLATION.md` | Procédure opérationnelle complète de reconstruction |

---

## 4. Documentation des évolutions du projet

Ces documents expliquent les couches versionnées qui ont enrichi le projet.

| Version | Document | Apport principal |
|---|---|---|
| V3 | `13_WORKSTATION_V3.md` | Workstation VS Code/WezTerm/OpenSSH/qualité |
| V4 | `14_WINDOWS_OPTIMIZATION_V4.md` | Optimisations Windows réversibles et benchmarks |
| V5 | `15_HARDWARE_QUALIFICATION_V5.md` | Qualification ciblée du matériel réel |
| V6 | `17_WSL2_TUNING_V6.md` | Tuning WSL2 adapté au Ryzen 7 7700 / 48 Go |
| V7 | `18_BACKUP_DISASTER_RECOVERY_V7.md` | Golden Backup et reprise après incident |
| V7+ | `19_OPENCLAW_OPENROUTER_WINDOWS.md` | OpenClaw/OpenRouter sous Windows |
| V8 | `20_WINDOWS_RESPONSIVENESS_V8.md` | Réactivité Windows mesurée et réversible |
| V9 | `21_ORCHESTRATION_IDEMPOTENCE_V9.md` | Orchestration machine-first et idempotence |
| V10 | `21_DEVOPS_TERMINAL_V10.md` | WezTerm + Bash DevOps + VS Code |
| V11 | `22_SYSTEM_UPDATE_MANAGER_V11.md` | Gestionnaire global de mises à jour |
| V12 | `23_INTERACTIVE_CONTROL_CENTER_V12.md` | Menu interactif central |
| V13 docs | `24_GUIDE_MAITRE_V13.md` | Documentation consolidée et parcours débutant |

Les numéros identiques `21_*` sont historiques : ils sont conservés pour éviter de casser les références existantes.

---

## 5. Trois niveaux de commande à connaître

### Niveau 1 — le menu

À privilégier au quotidien :

```powershell
.\menu.ps1
```

### Niveau 2 — les orchestrateurs

Pour comprendre précisément ce qui se passe :

```powershell
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Apply
.\install.ps1 -Mode Verify
.\install.ps1 -Mode Rollback

.\update.ps1 -Mode Audit
.\update.ps1 -Mode Apply
.\update.ps1 -Mode Verify
```

### Niveau 3 — les composants spécialisés

À utiliser pour le dépannage ou les validations ciblées, par exemple :

```text
scripts/bootstrap/
scripts/windows/
scripts/wsl/
scripts/backup/
scripts/updates/
scripts/defender/
```

Un débutant ne doit normalement pas commencer par ces scripts.

---

## 6. Ce que le projet automatise — et ce qu'il refuse d'automatiser

### Automatisé / géré

- inventaire et préflight de la machine ;
- applications WinGet autorisées ;
- réglages Windows réversibles ;
- profils d'optimisation ;
- WSL2 et Ubuntu cible ;
- stack DevOps ;
- VS Code / WezTerm / terminal Bash ;
- OpenSSH Client ;
- OpenClaw/OpenRouter selon le contrôle-plane versionné ;
- mises à jour Windows/applications/WSL/Ubuntu/VS Code ;
- sauvegarde Windows + WSL ;
- rapports, journaux et validations.

### Volontairement manuel ou guidé

- flash BIOS/UEFI ;
- modification PBO/overclocking ;
- validation de stabilité RAM 6000 MT/s ;
- contrôle physique des SSD M.2 et du refroidissement ;
- drivers Windows Update facultatifs par défaut ;
- installation de logiciels sans identifiant WinGet fiable ;
- restauration bare-metal destructive ;
- suppression automatique d'OpenClaw ou de données utilisateur.

Cette séparation est un principe de sécurité du projet, pas une limitation accidentelle.

---

## 7. Source de vérité

Quand une documentation et le code semblent diverger, l'ordre de confiance est :

1. l'état réel de la machine ;
2. les configurations versionnées dans `config/` et `manifests/` ;
3. les scripts actuels ;
4. la documentation ;
5. les anciens exemples ou captures d'écran.

La documentation V13 est conçue pour refléter le `main` V12 actuel, mais les versions de BIOS, drivers et Windows évoluent : pour ces éléments, toujours vérifier la source officielle du constructeur avant installation.
