# Hardware & Drivers Qualification V5

## Objectif

Cette V5 qualifie la machine réelle sans transformer le poste en banc d'overclocking.

Priorités, dans cet ordre :

1. stabilité ;
2. performances matérielles attendues ;
3. températures et santé du stockage ;
4. compatibilité WSL2 / virtualisation ;
5. gaming 1440p 240 Hz ;
6. reproductibilité et preuve.

La politique par défaut est volontairement conservatrice : **aucun PBO Advanced, Curve Optimizer, undervolt GPU, timing RAM manuel ou plan Ultimate Performance n'est appliqué automatiquement**.

## Matériel cible

- AMD Ryzen 7 7700 — 8 cœurs / 16 threads, 65 W ;
- MSI MAG B850M Mortar WiFi ;
- 48 Go DDR5, 2×24 Go, cible 6000 MT/s uniquement si stable ;
- Intel Arc B580 12 Go ;
- 2× Crucial T705 PCIe 5.0 NVMe ;
- DeepCool LD240WH 240 mm ;
- Corsair RM650e 650 W ;
- ASUS Prime AP201 ;
- ROG Strix OLED XG27AQDMES — 2560×1440, 240 Hz.

La cible machine est versionnée dans :

```text
config/hardware/target-v5.json
```

## 1. Philosophie CPU — Ryzen 7 7700

Le Ryzen 7 7700 possède Precision Boost 2 et un TDP par défaut de 65 W. Il supporte PBO et Curve Optimizer, mais la V5 ne les active pas automatiquement.

Cible quotidienne :

```text
CPU stock
└── Precision Boost 2 automatique
    ├── pas de PBO Advanced forcé
    ├── pas de Curve Optimizer arbitraire
    └── pas de tension manuelle
```

Pourquoi :

- les gains d'un réglage PBO/CO varient d'un exemplaire de CPU à l'autre ;
- la stabilité DevOps compte davantage qu'un petit gain de benchmark ;
- Kubernetes, compression, Terraform, compilation et VM peuvent révéler des instabilités qu'un jeu court ne montre pas.

PBO/Curve Optimizer pourront être étudiés plus tard dans une branche expérimentale avec stress test avant/après, jamais dans le profil V5 stable.

## 2. Mémoire — 48 Go DDR5 6000

Le contrôleur mémoire du Ryzen 7 7700 possède une spécification JEDEC inférieure à 6000 MT/s ; 6000 MT/s est donc traité comme un profil d'overclocking mémoire.

### Séquence recommandée

1. premier démarrage aux paramètres mémoire par défaut ;
2. mise à jour vers un BIOS MSI stable ;
3. vérifier que la machine est saine ;
4. activer le profil mémoire 6000 du kit ;
5. redémarrer ;
6. vérifier sous Windows que `ConfiguredClockSpeed` est bien à 6000 ;
7. exécuter un vrai test de stabilité mémoire ;
8. seulement ensuite enregistrer la preuve V5 `Memory6000Stable`.

Ne pas toucher manuellement aux tensions ou sous-timings dans la V5.

### Contrôle Windows

```powershell
Get-CimInstance Win32_PhysicalMemory |
    Select-Object Manufacturer,PartNumber,Capacity,Speed,ConfiguredClockSpeed
```

La qualification automatique exige que les barrettes présentes soient configurées à au moins 6000 MHz déclarés par Windows.

## 3. UEFI / BIOS MSI

Avant Windows définitif, vérifier :

```text
Boot Mode                  UEFI
CSM / Legacy               Disabled
Secure Boot                Enabled
TPM / fTPM                 Enabled
SVM / CPU Virtualization   Enabled
Above 4G Decoding          Enabled
Re-Size BAR                Enabled
Memory profile             6000 seulement si stable
```

### Pourquoi Above 4G + ReBAR

Intel demande Resizable BAR activé pour les performances optimales des GPU Arc B-Series. Le guide Intel demande également UEFI, CSM désactivé, Above 4G Decoding et Re-Size BAR.

La V5 ne prétend pas détecter directement le réglage UEFI ReBAR depuis une API Windows générique. Il doit être :

1. vérifié dans l'UEFI ;
2. confirmé après installation du pilote dans Intel Graphics Software ou Intel Driver & Support Assistant ;
3. enregistré dans la checklist manuelle V5.

## 4. GPU — Intel Arc B580

### Placement

La carte doit être placée dans le slot principal :

```text
PCI_E1
└── PCIe CPU direct
    └── jusqu'à PCIe 5.0 x16 avec Ryzen 7000
```

### Réglages retenus

- UEFI + GPT ;
- CSM désactivé ;
- Above 4G Decoding activé ;
- Re-Size BAR activé ;
- pilote Intel Arc récent et stable ;
- Windows Game Mode conservé ;
- VRR activé quand utile ;
- pas d'undervolt/overclock GPU automatique.

### Vérifier le pilote

```powershell
Get-CimInstance Win32_VideoController |
    Select-Object Name,DriverVersion,DriverDate,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate
```

### Vérifier ReBAR

Utiliser Intel Graphics Software ou Intel Driver & Support Assistant. La preuve est ensuite enregistrée avec :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 `
  -Mode Record `
  -ResizableBarEnabled
```

## 5. SSD — 2× Crucial T705

La carte mère possède trois slots M.2, mais ils ne sont pas équivalents avec un Ryzen 7000 :

```text
M2_1  CPU  PCIe 5.0 x4   <- T705
M2_2  CPU  PCIe 5.0 x4   <- T705
M2_3  B850 PCIe 4.0 x2   <- ne pas utiliser pour un des deux T705 principaux
```

La V5 exige donc physiquement :

```text
T705 #1 -> M2_1
T705 #2 -> M2_2
```

Windows ne fournit pas une preuve portable et fiable du nom sérigraphié du slot M.2. Ce point reste manuel.

### Refroidissement

Un T705 Gen5 peut générer suffisamment de chaleur pour perdre des performances sans refroidissement adapté. Les versions sans dissipateur doivent utiliser le dissipateur de la carte mère ou un dissipateur alternatif.

Pour chaque T705 :

- retirer les films de protection des pads thermiques ;
- utiliser le M.2 Shield Frozr / dissipateur adapté ;
- vérifier le contact du pad ;
- conserver un flux d'air dans l'AP201 ;
- surveiller température et santé avec Crucial Storage Executive.

### Ce que la V5 ne fait pas

- pas de Secure Erase ;
- pas de Sanitize ;
- pas de RAID automatique ;
- pas de Momentum Cache automatique ;
- pas de benchmark massif qui écrit des centaines de Go ;
- pas de désactivation de la protection Windows pour gagner un score synthétique.

### Contrôle santé

```powershell
Get-PhysicalDisk |
    Select-Object FriendlyName,Model,HealthStatus,OperationalStatus,BusType,Size
```

Inventaire détaillé :

```powershell
.\scripts\windows\50_hardware_inventory.ps1
```

Le script tente aussi de lire les compteurs de fiabilité/ température lorsque le pilote de stockage les expose.

## 6. Écran OLED 1440p 240 Hz

Cible :

```text
2560 x 1440
240 Hz
VRR / Adaptive Sync selon usage
OLED Care Pro actif
Neo Proximity Sensor selon préférence
HDR configuré seulement si utilisé
```

Le validateur accepte 239 Hz ou plus afin d'éviter un faux KO dû à la représentation du taux de rafraîchissement.

Vérification Windows :

```powershell
Get-CimInstance Win32_VideoController |
    Select-Object Name,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate
```

Conserver les fonctions de protection OLED. Ne pas désactiver les mécanismes de soin de dalle pour gagner un avantage inexistant en DevOps.

## 7. Refroidissement CPU / boîtier

### Ryzen 7 7700 + AIO 240 mm

Objectif : stabilité et bruit raisonnable, pas une température minimale à tout prix.

Recommandation :

- pompe selon le mode recommandé par le constructeur ;
- ventilateurs radiateur pilotés par température CPU ;
- courbe progressive ;
- ventilateurs de boîtier assurant un flux frais sur GPU et M.2 ;
- éviter les courbes qui montent/descendent agressivement à chaque pic court du Ryzen.

Le 7700 peut fonctionner à des températures élevées dans sa logique de boost. Une température seule ne suffit pas à conclure à un problème : il faut regarder fréquence, stabilité, throttling et bruit.

## 8. Alimentation

La Corsair RM650e 650 W reste cohérente avec la configuration. Intel indique 600 W minimum pour sa B580 Limited Edition ; la consommation réelle dépend du modèle de carte.

Aucun réglage logiciel V5 ne modifie les limites de puissance GPU/CPU.

## 9. Pilotes — ordre propre

Après installation de Windows :

1. Windows Update jusqu'à état propre ;
2. pilote chipset AMD depuis AMD ;
3. pilote Intel Arc depuis Intel ;
4. LAN / Wi-Fi / Bluetooth depuis MSI si nécessaire ;
5. audio MSI/Realtek ;
6. périphériques spécifiques uniquement si requis.

Ne pas utiliser de « driver updater » tiers générique.

### Inventaire des pilotes

Le rapport :

```text
reports/hardware/hardware-inventory-v5.json
```

contient les pilotes AMD/Intel/réseau/audio que Windows expose.

La V5 ne fige pas de numéro de version de pilote dans Git : une version correcte aujourd'hui deviendrait obsolète. La règle est de vérifier les sources constructeur au moment de l'installation.

## 10. Plan d'alimentation

Cible V5 : **Équilibré / Balanced**.

Raison : le scheduler et le boost moderne du Ryzen savent monter rapidement en fréquence sans garder inutilement tous les composants dans un état de consommation élevé.

Vérifier :

```powershell
powercfg /GetActiveScheme
```

Le validateur cible le GUID Windows standard du plan Balanced.

## 11. Qualification automatique

Inventaire :

```powershell
.\scripts\windows\50_hardware_inventory.ps1
```

Qualification automatique :

```powershell
.\scripts\bootstrap\13_validate_hardware_v5.ps1
```

Contrôles stricts :

- Ryzen 7 7700 ;
- 8 cœurs / 16 threads ;
- virtualisation firmware active ;
- au moins 48 Go de RAM ;
- mémoire configurée à 6000 ;
- MSI B850M Mortar ;
- Intel Arc B580 + pilote ;
- au moins deux Crucial T705 ;
- T705 sains ;
- C: et D: NTFS ;
- disque système GPT ;
- Secure Boot ;
- TPM prêt ;
- plan Balanced ;
- TRIM actif ;
- 2560×1440 à au moins 239 Hz.

Rapport :

```text
reports/hardware/validation-hardware-v5.json
```

## 12. Qualification manuelle

Afficher la checklist :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Show
```

Enregistrer les contrôles **au fur et à mesure**, après les avoir réellement réalisés.

Exemple après validation ReBAR :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 `
  -Mode Record `
  -Above4GEnabled `
  -ResizableBarEnabled
```

Après vérification physique des SSD :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 `
  -Mode Record `
  -T705InM2Slots `
  -T705CoolingVerified
```

Après test mémoire et revue BIOS/pilotes :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 `
  -Mode Record `
  -UefiCsmDisabled `
  -Memory6000Stable `
  -LatestStableBiosReviewed `
  -CurrentVendorDriversReviewed
```

Vérifier que toutes les preuves sont présentes :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Verify
```

Verdict attendu :

```text
VERDICT: V5 HARDWARE MANUAL CHECKS READY
```

## 13. Verdict V5 complet

Une fois les contrôles manuels enregistrés :

```powershell
.\scripts\bootstrap\13_validate_hardware_v5.ps1 -RequireManualChecks
```

Verdict attendu :

```text
VERDICT: V5 HARDWARE READY
```

Le rapport et les preuves locales sont dans `reports/` et `state/`, tous deux ignorés par Git.

## 14. Ce qui peut être optimisé plus tard, séparément

Les sujets suivants ne font pas partie du profil stable V5 :

- PBO Advanced ;
- Curve Optimizer négatif ;
- timings DDR5 manuels ;
- undervolt/overclock Arc B580 ;
- ASPM GPU expérimental ;
- over-provisioning SSD imposé ;
- Momentum Cache ;
- plan Ultimate Performance.

Ils devront disposer d'une baseline, d'un test de stabilité, de températures et d'un rollback avant toute intégration.
