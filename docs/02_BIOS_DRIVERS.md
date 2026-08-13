# BIOS, UEFI et pilotes

## Politique

La workstation vise les performances attendues du matériel **sans appliquer d'overclocking ou de modification firmware automatique**.

Le dépôt peut observer et qualifier une partie de l'état matériel, mais les réglages UEFI restent des décisions humaines.

Guide matériel : [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

---

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

Resizable BAR et Above 4G doivent être vérifiés manuellement : un script PowerShell générique ne constitue pas une preuve fiable de tous les réglages UEFI.

---

## CPU — Ryzen 7 7700

Politique actuelle :

- fonctionnement stock ;
- Precision Boost 2 conservé ;
- pas de PBO Advanced automatique ;
- pas de Curve Optimizer automatique ;
- pas de tension CPU manuelle appliquée par le dépôt.

L'objectif est une workstation fiable, pas un profil d'overclocking.

---

## Mémoire

La cible quotidienne peut être 6000 MT/s si le kit est réellement stable.

Vérification Windows :

```powershell
Get-CimInstance Win32_PhysicalMemory |
    Select-Object Manufacturer,PartNumber,Capacity,Speed,ConfiguredClockSpeed
```

Une fréquence affichée ne prouve pas la stabilité. Le résultat complet doit être associé à un test mémoire et à la checklist manuelle lorsque nécessaire.

En cas de crashs inexpliqués ou après un changement BIOS important, revenir temporairement à des paramètres mémoire plus conservateurs est préférable à masquer une instabilité.

---

## SSD

Pour les deux Crucial T705 :

```text
M2_1 -> emplacement prioritaire PCIe 5.0 x4
M2_2 -> second emplacement prévu pour le T705
```

Le montage physique, les capacités exactes des slots et le refroidissement doivent être vérifiés par rapport à la carte mère et au manuel MSI.

Le dépôt ne déplace évidemment aucun SSD et ne flashe pas de firmware stockage.

---

## Intel Arc B580

La plateforme cible prévoit :

- Above 4G Decoding actif ;
- Resizable BAR actif ;
- pilote Intel Arc stable ;
- aucun OC/undervolt automatique ;
- affichage correctement détecté.

Les réglages UEFI liés au GPU restent des preuves manuelles.

---

## Ordre conseillé des pilotes

Après un premier Windows Update stable :

1. AMD Chipset depuis AMD ;
2. Intel Arc Graphics depuis Intel ;
3. LAN / Wi-Fi / Bluetooth MSI si nécessaire ;
4. audio MSI/Realtek si nécessaire ;
5. périphériques spécifiques uniquement lorsqu'un besoin réel existe.

Évite les logiciels génériques de type « driver updater ».

Le dépôt ne fige pas les numéros des pilotes Windows dans la documentation : ils évoluent rapidement. Il qualifie la version réellement installée et laisse la vérification du package courant aux sources officielles AMD, Intel, MSI ou Microsoft.

---

## Inventaire

```powershell
.\scripts\windows\50_hardware_inventory.ps1
```

Les rapports matériels sont écrits sous :

```text
reports/hardware/
```

---

## Checklist manuelle

Afficher les contrôles :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Show
```

Enregistrer les confirmations sur la vraie machine :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Record -Interactive
```

---

## Qualification finale

La voie utilisateur recommandée est :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

Elle agrège les informations observables et les preuves manuelles disponibles.

Le nom de certains scripts ou fichiers internes peut encore contenir un suffixe historique ; cela fait partie de l'implémentation. Pour l'utilisateur, le contrat actuel est simplement **la qualification matérielle de la workstation**.

---

## Frontières de sécurité

Le dépôt ne doit jamais automatiquement :

- flasher le BIOS ;
- modifier PBO / Curve Optimizer ;
- appliquer des timings mémoire ;
- forcer une fréquence DDR5 ;
- activer ou désactiver ReBAR à l'aveugle ;
- installer tous les drivers facultatifs ;
- flasher le firmware SSD ;
- masquer une instabilité matérielle pour obtenir un verdict vert.

Une preuve manquante doit rester une **action requise**, pas devenir un faux succès.
