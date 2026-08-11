# BIOS et pilotes

## Politique V5

La configuration stable vise les performances attendues du matériel **sans appliquer d'overclocking automatique**.

Guide détaillé :

```text
docs/15_HARDWARE_QUALIFICATION_V5.md
```

## Réglages UEFI à contrôler

```text
Boot UEFI                 Enabled
CSM / Legacy              Disabled
Secure Boot               Enabled
TPM / fTPM                Enabled
SVM / virtualisation AMD  Enabled
Above 4G Decoding         Enabled
Resizable BAR             Enabled
Mémoire                    6000 MT/s uniquement si stable
```

Intel demande Resizable BAR actif pour les performances optimales des GPU Arc B-Series. La V5 exige donc une confirmation manuelle ReBAR après installation du pilote Intel, car un script PowerShell générique ne constitue pas une preuve fiable du réglage UEFI.

## CPU

Ryzen 7 7700 :

- configuration stock ;
- Precision Boost 2 conservé ;
- pas de PBO Advanced automatique ;
- pas de Curve Optimizer automatique ;
- pas de tension CPU manuelle.

## Mémoire

La cible quotidienne est 6000 MT/s si le kit est réellement stable.

Vérifier sous Windows :

```powershell
Get-CimInstance Win32_PhysicalMemory |
    Select-Object Manufacturer,PartNumber,Capacity,Speed,ConfiguredClockSpeed
```

La V5 ne considère pas 6000 comme valide tant qu'un test de stabilité mémoire n'a pas été réalisé et enregistré dans la checklist manuelle.

## SSD

Avec Ryzen 7000 sur la MAG B850M Mortar WiFi :

```text
M2_1 -> PCIe 5.0 x4 -> Crucial T705
M2_2 -> PCIe 5.0 x4 -> Crucial T705
M2_3 -> PCIe 4.0 x2 -> ne pas utiliser pour un T705 principal
```

Les deux T705 doivent disposer d'un dissipateur adapté et d'un flux d'air correct.

## Pilotes

Ordre conseillé après Windows Update :

1. AMD Chipset depuis AMD ;
2. Intel Arc Graphics depuis Intel ;
3. LAN / Wi-Fi / Bluetooth MSI si nécessaire ;
4. audio MSI/Realtek ;
5. périphériques spécifiques uniquement si requis.

Éviter les outils tiers de type « driver updater » générique.

Le dépôt ne fige pas de numéro de version de pilote, car ces versions évoluent. Il inventorie la version réellement installée dans :

```text
reports/hardware/hardware-inventory-v5.json
```

## Commandes V5

Inventaire :

```powershell
.\scripts\windows\50_hardware_inventory.ps1
```

Checklist manuelle :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Show
```

Qualification automatique :

```powershell
.\scripts\bootstrap\13_validate_hardware_v5.ps1
```

Qualification finale avec preuves UEFI / placement / stabilité :

```powershell
.\scripts\bootstrap\13_validate_hardware_v5.ps1 -RequireManualChecks
```
