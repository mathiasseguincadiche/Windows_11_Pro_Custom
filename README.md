# Windows 11 Pro Custom

Configuration reproductible d'un poste **Windows 11 Pro** sur mesure, orienté **DevOps/Ops**, WSL2, gaming, optimisation Windows réversible et reprise après incident.

## Architecture validée

- SSD système Crucial T705 : `C:` en **NTFS**.
- SSD DATA Crucial T705 : `D:` en **NTFS**.
- **Aucune partition EXT4 physique** et aucun dual boot.
- Ubuntu WSL2 est stocké sous `D:\WSL\Ubuntu-DevOps\` ; son VHDX contient le filesystem Linux interne.
- Le swap WSL est stocké séparément sous `D:\WSL\swap\wsl-swap.vhdx`.
- Les dépôts DevOps utilisés par Linux restent dans `/home/<user>/projects`, pas dans `/mnt/c` ou `/mnt/d`.
- WSL2 quotidien V6 : **8 threads, 20 Go RAM, 8 Go swap**, réseau `mirrored`, DNS tunneling et firewall WSL/Hyper-V.
- WSL2 lab-heavy V6 : **12 threads, 28 Go RAM, 12 Go swap**.
- Docker Engine tourne directement dans Ubuntu WSL2 ; Docker Desktop n'est pas requis.
- Microsoft Defender reste actif et toute exclusion est **deny-by-default** puis justifiée par mesure.
- PowerShell 7 stable est installé dans le socle Windows via `Microsoft.PowerShell` ; Windows PowerShell 5.1 reste présent pour compatibilité.
- Le client OpenSSH Windows est installé et géré par le dépôt pour VS Code Remote - SSH ; le serveur OpenSSH Windows n'est pas installé.
- VS Code couvre WSL, Remote - SSH et SFTP/FTP.
- Les tweaks Windows, VS Code, WezTerm et les profils V4 possèdent Audit, Apply, Verify et Rollback.
- La V5 matériel est **observationnelle** : elle qualifie mais ne modifie jamais automatiquement BIOS, PBO, RAM, GPU ou stockage.
- La V7 protège l'état réel du poste avec une image Windows `C:` + `D:` + volumes critiques et un export WSL2 VHDX indépendant sur un disque de sauvegarde séparé.
- La restauration V7 est **guidée mais jamais destructive automatiquement**.

## Matériel cible

- AMD Ryzen 7 7700 — 8 cœurs / 16 threads
- MSI MAG B850M Mortar WiFi
- 48 Go DDR5 6000 MT/s CL30
- Intel Arc B580 12 Go
- 2× Crucial T705 PCIe 5.0
- DeepCool LD240WH
- Corsair RM650e 650 W
- ASUS Prime AP201
- ROG Strix OLED XG27AQDMES 1440p 240 Hz
- Logitech Brio 100

## Hardware Qualification V5

Politique stable :

```text
Ryzen 7 7700       stock / Precision Boost 2
DDR5               6000 seulement si stable
Arc B580            ReBAR + Above 4G vérifiés
T705 #1             M2_1 PCIe 5.0 x4
T705 #2             M2_2 PCIe 5.0 x4
Écran               2560×1440 à ~240 Hz
Plan alimentation   Balanced
```

La V5 contrôle automatiquement CPU, RAM, carte mère, GPU, pilotes, SSD, GPT, Secure Boot, TPM, SVM, TRIM et affichage. Les éléments non prouvables proprement via une API Windows générique (ReBAR UEFI, Above 4G, emplacement physique M.2, refroidissement et test de stabilité mémoire) sont enregistrés dans une checklist manuelle explicite.

Inventaire :

```powershell
.\scripts\windows\50_hardware_inventory.ps1
```

Checklist :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Show
```

Qualification finale :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

Verdict attendu :

```text
VERDICT: V5 HARDWARE READY
```

Guide complet :

```text
docs/15_HARDWARE_QUALIFICATION_V5.md
```

## WSL2 V6 — profil matériel

Le profil quotidien est dimensionné pour le Ryzen 7 7700 et les 48 Go de RAM :

```text
standard
├── 20 Go RAM
├── 8 threads
├── 8 Go swap sur D:\WSL\swap\wsl-swap.vhdx
├── mirrored networking
├── DNS tunneling
├── firewall actif
├── autoMemoryReclaim=gradual
├── sparseVhd=true
└── nestedVirtualization=false
```

Le profil lourd est réservé aux labs :

```text
lab-heavy
├── 28 Go RAM
├── 12 threads
└── 12 Go swap
```

Le profil `nat-fallback` garde le budget `standard` mais bascule temporairement le réseau en NAT.

Guide de tuning V6 :

```text
docs/17_WSL2_TUNING_V6.md
```

Qualification runtime :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

Verdict attendu :

```text
VERDICT: V6 WSL2 PLATFORM READY
```

Le validateur compare le profil versionné avec `%UserProfile%\.wslconfig` puis mesure depuis Ubuntu les CPU, RAM, swap, PID 1, filesystem HOME et présence de `~/projects`. Il vérifie également la présence de PowerShell 7 côté Windows.

## Backup & Disaster Recovery V7

La V7 ajoute quatre protections complémentaires :

```text
System Restore
      ↓
régression Windows légère

WindowsImageBackup
      ↓
C: + D: + volumes critiques
      ↓
récupération bare-metal depuis WinRE

WSL VHDX + SHA-256
      ↓
restauration Ubuntu indépendante

GitHub V1 → V7
      ↓
reconstruction reproductible si nécessaire
```

Politique :

```text
config/backup/v7-policy.json
```

Création du Golden Backup sur un disque USB NTFS séparé, exemple `E:` :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
```

La création :

- refuse une cible située sur le même disque physique que `C:` ou `D:` ;
- exige NTFS ;
- exige 100 Go libres minimum ;
- exige une cible USB par défaut ;
- vérifie WinRE ;
- tente un point de restauration ;
- arrête WSL ;
- crée l'image Windows avec `wbadmin` ;
- vérifie qu'une version récupérable est énumérée ;
- exporte Ubuntu en VHDX ;
- calcule et enregistre le SHA-256 ;
- écrit un manifest JSON.

Verdict de création :

```text
VERDICT: V7 GOLDEN BACKUP CREATED
```

Validation indépendante :

```powershell
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
```

Verdict attendu après une **vraie sauvegarde sur le PC** :

```text
VERDICT: V7 BACKUP READY
```

Génération d'un plan de restauration sans exécuter la restauration :

```powershell
.\install.ps1 -BackupAction RestorePlan -BackupTargetDrive E:
```

La V7 ne lance jamais automatiquement `wbadmin start sysrecovery`, ne reformate aucun disque et ne fait jamais `wsl --unregister` sur la distribution active. Une restauration WSL est d'abord importée sous `Ubuntu-Restore-V7` à côté de l'Ubuntu existant.

Guide complet :

```text
docs/18_BACKUP_DISASTER_RECOVERY_V7.md
```

## Stack DevOps WSL2

- Docker Engine + Compose + Buildx
- kubectl
- Helm
- Minikube
- kind
- Terraform
- AWS CLI v2
- Ansible Core
- GitHub CLI
- Trivy
- ShellCheck
- shfmt
- terraform-docs `v0.24.0`
- actionlint `v1.7.12`
- yq `v4.53.3`
- TFLint `v0.64.0`

Docker utilise le driver de logs `local` avec rotation afin d'éviter des journaux de conteneurs non bornés dans le VHDX.

## Guide WSL2 débutant → avancé

Le guide pédagogique principal est :

```text
docs/16_WSL2_GUIDE_COMPLET.md
```

Il part de zéro et couvre le modèle mental Windows/Linux, le premier lancement Ubuntu, les commandes Linux de base, les permissions, `sudo`, APT, Git, VS Code, les commandes WSL PowerShell, `.wslconfig`, `/etc/wsl.conf`, systemd, réseau, Docker, Kubernetes, Terraform, Ansible, sauvegardes, import/export, VHDX, dépannage, exercices et antisèches.

**Les valeurs de ressources WSL2 de référence sont celles de la V6 dans `docs/17_WSL2_TUNING_V6.md` et `config/wsl/*.wslconfig`.**

Règle centrale :

```text
outils Linux -> fichiers de projet Linux
               /home/<user>/projects
```

## Workstation DevOps

Windows héberge VS Code, WezTerm et PowerShell 7.

VS Code est préparé pour :

- WSL — `ms-vscode-remote.remote-wsl` ;
- Remote - SSH — `ms-vscode-remote.remote-ssh` ;
- SFTP / FTP — `Natizyskunk.sftp` ;
- Terraform ;
- Kubernetes ;
- Container Tools ;
- YAML ;
- GitHub Actions ;
- ShellCheck ;
- shell-format.

Le client Windows requis pour Remote - SSH est géré comme capacité système :

```text
OpenSSH.Client~~~~0.0.1.0
```

Exemples :

```text
config/vscode/ssh-config.example
config/vscode/sftp.example.json
```

`.vscode/sftp.json` est ignoré par Git pour éviter la publication accidentelle de secrets. SFTP avec clé SSH est préféré à FTP avec mot de passe.

WezTerm ouvre par défaut :

```text
wsl.exe -d Ubuntu --cd ~
```

Le profil shell Linux fournit les alias et complétions DevOps depuis `~/.config/windows11-pro-custom/devops.sh`.

## Socle applicatif Windows

Installation automatique WinGet quand un ID fiable est disponible :

```text
Visual Studio Code
PowerShell 7 stable
VLC
Notion
Firefox
Brave
FileZilla
WezTerm
LibreOffice
Steam
Notepad++
draw.io
Bitwarden
```

Installation conservée manuelle/contrôlée :

```text
MarkText
Microsoft Office
PDFgear
Files
```

WSL2 fait partie du socle système mais est provisionné par le bootstrap WSL, pas comme une application WinGet. OpenSSH Client est également provisionné comme capacité Windows et non comme package WinGet.

## Windows Optimization V4

WinUtil est utilisé comme **référence upstream** et non comme script distant exécuté automatiquement.

La V4 comprend quatre profils :

- `standard` — appliqué par défaut ;
- `privacy` — opt-in ;
- `gaming` — opt-in ;
- `optional` — tuning services limité et opt-in.

Le profil `standard` complète la base existante avec Activity History désactivé, WPBT bloqué, Delivery Optimization sans peer-to-peer et `End Task` dans la barre des tâches.

Le mapping WinUtil est versionné dans :

```text
config/winutil/mathias-winutil.json
```

### Audit

```powershell
.\install.ps1 -Mode Audit
```

### Apply — profil standard

```powershell
.\install.ps1 -Mode Apply
```

### Apply — standard + privacy + gaming

```powershell
.\install.ps1 -Mode Apply -OptimizationProfiles standard,privacy,gaming
```

Avant les modifications V4, le dépôt tente de créer un point de restauration Windows, capture un benchmark léger puis sauvegarde l'état Registry/services de chaque profil.

Rapports :

```text
reports/windows/v4-benchmark-before.json
reports/windows/v4-benchmark-after.json
reports/windows/v4-benchmark-comparison.json
reports/validation-v4.json
```

## Organisation

```text
Windows_11_Pro_Custom/
├── config/
│   ├── backup/
│   ├── defender/
│   ├── hardware/
│   ├── vscode/
│   ├── wezterm/
│   ├── winutil/
│   ├── windows/v4/
│   └── wsl/
├── docs/
├── manifests/
├── scripts/
│   ├── backup/
│   ├── bootstrap/
│   ├── defender/
│   ├── windows/
│   └── wsl/
└── .github/workflows/
```

## Installation principale

PowerShell administrateur :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Apply
```

PowerShell 7 est ensuite disponible via :

```powershell
pwsh
```

Après le premier lancement Ubuntu :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
wsl --shutdown
.\install.ps1 -Mode Verify -ValidateWsl -ValidateDevOps
```

Après vérification UEFI / ReBAR / M.2 / refroidissement / stabilité mémoire :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware -ValidateWsl -ValidateDevOps
```

Verdicts plateforme attendus :

```text
VERDICT: V3 WINDOWS READY
VERDICT: V3 DEVOPS READY
VERDICT: V4 WINDOWS OPTIMIZATION READY
VERDICT: V5 HARDWARE READY
VERDICT: V6 WSL2 PLATFORM READY
```

Puis, après création réelle du Golden Backup :

```text
VERDICT: V7 BACKUP READY
```

## Rollback et restauration

Rollback des réglages gérés par le dépôt :

```powershell
.\install.ps1 -Mode Rollback
```

La V5 matériel n'a pas de rollback matériel car elle ne modifie aucun réglage matériel.

Le client OpenSSH Windows possède un rollback à état initial : il n'est retiré que si le dépôt l'avait ajouté sur une machine où il était absent au départ.

La V7 est différente d'un rollback : elle crée et vérifie des sauvegardes, puis génère un plan de reprise. Les opérations de restauration potentiellement destructives restent manuelles.

## Defender performance

```powershell
.\scripts\defender\01_record.ps1 -Seconds 60
.\scripts\defender\02_report.ps1
.\scripts\defender\03_apply_approved_exclusions.ps1 -Mode Audit
```

`config/defender/exclusions.approved.json` est vide par défaut.

## Stockage

Audit TRIM :

```powershell
.\scripts\windows\21_storage_trim.ps1 -Mode Audit
```

ReTrim manuel si nécessaire :

```powershell
.\scripts\windows\21_storage_trim.ps1 -Mode Apply
```

La planification Windows d'optimisation des SSD n'est jamais désactivée par le dépôt.

## Documentation

- `docs/00_ARCHITECTURE.md` — architecture globale ;
- `docs/02_BIOS_DRIVERS.md` — BIOS et stratégie pilotes ;
- `docs/04_OPTIMISATION_WINDOWS.md` — stratégie Windows ;
- `docs/05_DEFENDER_PERFORMANCE.md` — Defender et I/O ;
- `docs/06_WSL2.md` — configuration WSL2 de référence ;
- `docs/07_DEVOPS_STACK.md` — stack Linux ;
- `docs/11_VALIDATION.md` — critères workstation/DevOps ;
- `docs/12_RUNBOOK_REINSTALLATION.md` — réinstallation ;
- `docs/13_WORKSTATION_V3.md` — VS Code, Remote SSH/SFTP, OpenSSH, WezTerm et PowerShell ;
- `docs/14_WINDOWS_OPTIMIZATION_V4.md` — profils V4 et mapping WinUtil ;
- `docs/15_HARDWARE_QUALIFICATION_V5.md` — tuning matériel stable et qualification ;
- `docs/16_WSL2_GUIDE_COMPLET.md` — guide pédagogique WSL2 débutant à avancé ;
- `docs/17_WSL2_TUNING_V6.md` — tuning WSL2 matériel et exploitation V6 ;
- `docs/18_BACKUP_DISASTER_RECOVERY_V7.md` — Golden Backup, contrôle d'intégrité et reprise après incident.

## Statut

- V1 : architecture Windows 11 Pro / NTFS / WSL2 / Defender — intégrée.
- V2 : tuning Windows réversible, Defender mesuré et stack DevOps — intégrée.
- V3 : workstation DevOps, qualité IaC et qualification stricte — intégrée.
- V4 : optimisation Windows 11 inspirée de WinUtil, profils réversibles et benchmarks — intégrée.
- V5 : qualification hardware ciblée + guide WSL2 complet — intégrée.
- V6 : tuning WSL2 matériel, PowerShell 7, OpenSSH Client et accès distant VS Code — intégrée.
- V7 : Golden Backup Windows + export WSL2 + SHA-256 + plan de reprise non destructif — périmètre complet et qualifié par CI ; première sauvegarde réelle requise avant le verdict runtime `V7 BACKUP READY`.
