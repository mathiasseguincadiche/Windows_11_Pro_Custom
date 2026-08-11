# Windows 11 Pro Custom

Configuration reproductible d'un poste **Windows 11 Pro** sur mesure, orienté **DevOps/Ops**, WSL2 et gaming.

## Principes validés

- SSD système Crucial T705 : `C:` en **NTFS**.
- SSD DATA Crucial T705 : `D:` en **NTFS**.
- **Aucune partition EXT4 physique** et aucun dual boot.
- Ubuntu WSL2 est stocké sous `D:\WSL\Ubuntu-DevOps\` ; son fichier VHDX contient le système de fichiers Linux interne.
- Les dépôts DevOps utilisés par Linux restent dans `/home/<user>/projects`, pas dans `/mnt/c` ou `/mnt/d`.
- WSL2 : 6 CPU, 16 Go RAM, 8 Go swap, réseau `mirrored` par défaut, profil NAT de secours.
- Microsoft Defender reste actif. Les optimisations sont décidées après mesure de l'impact I/O.
- Les changements Windows doivent être auditables, vérifiables et réversibles.

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

## Organisation

```text
Windows_11_Pro_Custom/
├── config/
│   └── wsl/
├── docs/
├── manifests/
├── scripts/
│   ├── bootstrap/
│   ├── defender/
│   └── wsl/
├── tests/
└── .github/workflows/
```

## Démarrage

Lancer PowerShell en administrateur :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Mode Audit
```

Une fois l'audit vérifié :

```powershell
.\install.ps1 -Mode Apply
```

`Apply` n'ajoute aucune exclusion Defender globale et ne formate aucun disque.

## Statut

V1 en construction sur `feat/windows11-devops-v1`.
