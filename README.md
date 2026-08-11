# Windows 11 Pro Custom

Configuration reproductible d'un poste **Windows 11 Pro** sur mesure, orienté **DevOps/Ops**, WSL2, gaming et optimisation Windows réversible.

## Architecture validée

- SSD système Crucial T705 : `C:` en **NTFS**.
- SSD DATA Crucial T705 : `D:` en **NTFS**.
- **Aucune partition EXT4 physique** et aucun dual boot.
- Ubuntu WSL2 est stocké sous `D:\WSL\Ubuntu-DevOps\` ; son VHDX contient le filesystem Linux interne.
- Les dépôts DevOps utilisés par Linux restent dans `/home/<user>/projects`, pas dans `/mnt/c` ou `/mnt/d`.
- WSL2 quotidien : 6 CPU, 16 Go RAM, 8 Go swap, réseau `mirrored`, DNS tunneling et firewall WSL/Hyper-V.
- Docker Engine tourne directement dans Ubuntu WSL2 ; Docker Desktop n'est pas requis.
- Microsoft Defender reste actif et toute exclusion est **deny-by-default** puis justifiée par mesure.
- Les tweaks Windows, VS Code, WezTerm et les profils V4 possèdent Audit, Apply, Verify et Rollback.
- La V5 matériel est **observationnelle** : elle qualifie mais ne modifie jamais automatiquement BIOS, PBO, RAM, GPU ou stockage.

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

Il part de zéro et couvre le modèle mental Windows/Linux, le premier lancement Ubuntu, les commandes Linux de base, les permissions, `sudo`, APT, Git, VS Code, les commandes WSL PowerShell, `.wslconfig`, `/etc/wsl.conf`, systemd, réseau mirrored, Docker, Kubernetes, Terraform, Ansible, sauvegardes, import/export, VHDX, dépannage, exercices et antisèches.

Règle centrale :

```text
outils Linux -> fichiers de projet Linux
               /home/<user>/projects
```

Microsoft recommande ce placement pour éviter les ralentissements liés aux accès croisés entre le système de fichiers Windows et le système de fichiers WSL.

## Workstation DevOps

Windows héberge VS Code et WezTerm. VS Code est préparé pour travailler directement dans WSL avec les extensions WSL, Terraform, Kubernetes, Container Tools, YAML, GitHub Actions, ShellCheck et shell-format.

WezTerm ouvre par défaut :

```text
wsl.exe -d Ubuntu --cd ~
```

Le profil shell Linux fournit les alias et complétions DevOps depuis `~/.config/windows11-pro-custom/devops.sh`.

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

Ce fichier est une référence de décision, pas un export WinUtil annoncé comme directement importable.

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

Le benchmark ne lance aucun test synthétique générant de gros volumes d'écritures sur les SSD.

## Organisation

```text
Windows_11_Pro_Custom/
├── config/
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

Après le premier lancement Ubuntu :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
wsl --shutdown
.\install.ps1 -Mode Verify -ValidateDevOps
```

Après vérification UEFI / ReBAR / M.2 / refroidissement / stabilité mémoire :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware -ValidateDevOps
```

Verdicts attendus :

```text
VERDICT: V3 WINDOWS READY
VERDICT: V3 DEVOPS READY
VERDICT: V4 WINDOWS OPTIMIZATION READY
VERDICT: V5 HARDWARE READY
```

## Rollback

Rollback des réglages gérés par le dépôt :

```powershell
.\install.ps1 -Mode Rollback
```

Sans paramètre explicite, le rollback V4 détecte les profils possédant une sauvegarde initiale et les restaure. Il restaure aussi les réglages Windows historiques et les configurations VS Code/WezTerm gérées par le dépôt.

La V5 matériel n'a pas de rollback matériel car elle ne modifie aucun réglage matériel.

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
- `docs/06_WSL2.md` — démarrage rapide WSL2 ;
- `docs/07_DEVOPS_STACK.md` — stack Linux ;
- `docs/11_VALIDATION.md` — critères workstation/DevOps ;
- `docs/12_RUNBOOK_REINSTALLATION.md` — réinstallation ;
- `docs/13_WORKSTATION_V3.md` — VS Code, WezTerm et profil shell ;
- `docs/14_WINDOWS_OPTIMIZATION_V4.md` — profils V4 et mapping WinUtil ;
- `docs/15_HARDWARE_QUALIFICATION_V5.md` — tuning matériel stable et qualification ;
- `docs/16_WSL2_GUIDE_COMPLET.md` — guide pédagogique WSL2 débutant à avancé.

## Statut

- V1 : architecture Windows 11 Pro / NTFS / WSL2 / Defender — intégrée.
- V2 : tuning Windows réversible, Defender mesuré et stack DevOps — intégrée.
- V3 : workstation DevOps, qualité IaC et qualification stricte — intégrée.
- V4 : optimisation Windows 11 inspirée de WinUtil, profils réversibles et benchmarks — intégrée.
- V5 : qualification hardware ciblée + guide WSL2 complet — candidate à fusion après CI verte.
