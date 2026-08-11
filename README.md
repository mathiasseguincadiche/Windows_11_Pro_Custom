# Windows 11 Pro Custom

Configuration reproductible d'un poste **Windows 11 Pro** sur mesure, orienté **DevOps/Ops**, WSL2 et gaming.

## Architecture validée

- SSD système Crucial T705 : `C:` en **NTFS**.
- SSD DATA Crucial T705 : `D:` en **NTFS**.
- **Aucune partition EXT4 physique** et aucun dual boot.
- Ubuntu WSL2 est stocké sous `D:\WSL\Ubuntu-DevOps\` ; son VHDX contient le filesystem Linux interne.
- Les dépôts DevOps utilisés par Linux restent dans `/home/<user>/projects`, pas dans `/mnt/c` ou `/mnt/d`.
- WSL2 quotidien : 6 CPU, 16 Go RAM, 8 Go swap, réseau `mirrored`, DNS tunneling et firewall WSL/Hyper-V.
- Docker Engine tourne directement dans Ubuntu WSL2 ; Docker Desktop n'est pas requis.
- Microsoft Defender reste actif et toute exclusion est **deny-by-default** puis justifiée par mesure.
- Les tweaks Windows, VS Code et WezTerm possèdent Audit, Apply, Verify et Rollback.

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

## Stack DevOps WSL2 V3

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

## Workstation V3

Windows héberge VS Code et WezTerm. VS Code est préparé pour travailler directement dans WSL avec les extensions WSL, Terraform, Kubernetes, Container Tools, YAML, GitHub Actions, ShellCheck et shell-format.

WezTerm ouvre par défaut :

```text
wsl.exe -d Ubuntu --cd ~
```

Le profil shell Linux fournit les alias et complétions DevOps depuis `~/.config/windows11-pro-custom/devops.sh`.

## Organisation

```text
Windows_11_Pro_Custom/
├── config/
│   ├── defender/
│   ├── vscode/
│   ├── wezterm/
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

## 1. Audit avant modification

PowerShell administrateur :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Mode Audit
```

L'audit contrôle notamment le matériel, les volumes C:/D:, NTFS, TRIM, le plan d'alimentation, la mémoire, le GPU, Defender, WSL et les configurations du poste de travail.

## 2. Application Windows + WSL2

```powershell
.\install.ps1 -Mode Apply
```

Ce passage installe les applications WinGet validées, applique les tweaks Windows réversibles, prépare WSL2 et configure VS Code/WezTerm. Il ne formate aucun disque et n'ajoute aucune exclusion Defender tant que le manifeste d'exclusions reste vide.

## 3. Premier lancement Ubuntu

Lancer Ubuntu une première fois afin de créer l'utilisateur Linux, puis revenir dans PowerShell administrateur :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

Ce passage installe la stack DevOps V3, les outils qualité IaC, le profil shell et les extensions VS Code dans l'hôte WSL.

## 4. Qualification complète V3

Fermer WSL pour appliquer l'appartenance au groupe Docker :

```powershell
wsl --shutdown
```

Puis :

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

Verdicts attendus :

```text
VERDICT: V3 WINDOWS READY
VERDICT: V3 DEVOPS READY
```

## Rollback des réglages gérés par le dépôt

```powershell
.\install.ps1 -Mode Rollback
```

Le rollback restaure les réglages Windows sauvegardés, les configurations VS Code/WezTerm initiales et retire uniquement les exclusions Defender que ce dépôt aurait ajoutées. Il ne désinstalle pas les applications, WSL2 ou la stack DevOps.

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
- `docs/05_DEFENDER_PERFORMANCE.md` — Defender et I/O ;
- `docs/06_WSL2.md` — WSL2 ;
- `docs/07_DEVOPS_STACK.md` — stack Linux ;
- `docs/11_VALIDATION.md` — critères V3 ;
- `docs/12_RUNBOOK_REINSTALLATION.md` — réinstallation ;
- `docs/13_WORKSTATION_V3.md` — VS Code, WezTerm et profil shell.

## Statut

- V1 : architecture Windows 11 Pro / NTFS / WSL2 / Defender — intégrée.
- V2 : tuning Windows réversible, Defender mesuré et stack DevOps — intégrée.
- V3 : workstation DevOps, qualité IaC, qualification stricte et CI de sécurité — périmètre complet.
