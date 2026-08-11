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
- Les tweaks Windows possèdent Audit, Apply, Verify et Rollback.

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

Docker utilise le driver de logs `local` avec rotation afin d'éviter des journaux de conteneurs non bornés dans le VHDX.

## Organisation

```text
Windows_11_Pro_Custom/
├── config/
│   ├── defender/
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

L'audit contrôle notamment le matériel, les volumes C:/D:, NTFS, TRIM, le plan d'alimentation, la mémoire, le GPU, Defender et WSL.

## 2. Application Windows + WSL2

```powershell
.\install.ps1 -Mode Apply
```

Ce passage installe les applications WinGet validées, applique les tweaks Windows réversibles et prépare WSL2. Il ne formate aucun disque et n'ajoute aucune exclusion Defender tant que le manifeste d'exclusions reste vide.

## 3. Premier lancement Ubuntu

Lancer Ubuntu une première fois afin de créer l'utilisateur Linux, puis revenir dans PowerShell administrateur :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

## 4. Validation

Après l'installation Docker, fermer WSL :

```powershell
wsl --shutdown
```

Puis :

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

## Rollback des tweaks gérés par le dépôt

```powershell
.\install.ps1 -Mode Rollback
```

Le rollback restaure les valeurs Windows sauvegardées et retire uniquement les exclusions Defender que ce dépôt aurait ajoutées. Il ne désinstalle pas les applications, WSL2 ou la stack DevOps.

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

## Statut

- V1 : architecture Windows 11 Pro / NTFS / WSL2 / Defender — intégrée dans `main`.
- V2 : tuning Windows réversible, Defender mesuré, stack DevOps et contrôles renforcés — développée sur `feat/windows11-devops-v2`.
