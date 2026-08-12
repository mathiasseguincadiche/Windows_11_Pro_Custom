# Hardware & Drivers Qualification V5

## Objectif

La V5 qualifie la machine réelle et maintient Windows 11 en cohérence avec le matériel sans transformer le poste en banc d'overclocking.

Ordre de priorité :

1. stabilité ;
2. sécurité et compatibilité des pilotes ;
3. performances matérielles attendues ;
4. températures et santé du stockage ;
5. compatibilité WSL2 / virtualisation ;
6. gaming 1440p 240 Hz ;
7. reproductibilité et preuve.

La règle reste conservatrice : **aucun PBO Advanced, Curve Optimizer, undervolt/overclock GPU, timing DDR5 manuel, tweak HPET, désactivation d'offload réseau, flash BIOS/SSD ou plan Ultimate Performance n'est appliqué automatiquement**.

Les fichiers de référence sont :

```text
config/hardware/target-v5.json
config/hardware/symbiosis-v5.json
```

Le premier décrit la machine cible. Le second contient les baselines approuvées et les limites de sécurité de la qualification.

## Matériel cible

- AMD Ryzen 7 7700 — 8 cœurs / 16 threads, 65 W ;
- MSI MAG B850M Mortar WiFi ;
- 48 Go DDR5, 2×24 Go, cible 6000 MT/s uniquement si stable ;
- Intel Arc B580 12 Go ;
- 2× Crucial T705 PCIe 5.0 NVMe ;
- DeepCool LD240WH 240 mm ;
- Corsair RM650e 650 W ;
- ASUS Prime AP201 ;
- écran 2560×1440, 240 Hz.

## 1. CPU — Ryzen 7 7700

Cible quotidienne :

```text
Ryzen 7 7700 stock
└── Precision Boost 2
    ├── plan Windows Balanced
    ├── pas de PBO Advanced automatique
    ├── pas de Curve Optimizer automatique
    └── pas de tension manuelle
```

Le scheduler Windows, le firmware AMD et Precision Boost 2 doivent conserver la gestion dynamique du CPU. La V5 refuse les recettes génériques qui désactivent le core parking, les C-States ou changent les timers de démarrage sans mesure préalable.

## 2. Mémoire — 48 Go DDR5 6000

6000 MT/s est accepté uniquement après validation de stabilité.

Séquence :

1. BIOS stable ;
2. machine saine aux paramètres mémoire par défaut ;
3. activation du profil 6000 du kit ;
4. vérification de `ConfiguredClockSpeed` ;
5. test mémoire prolongé ;
6. enregistrement de la preuve `Memory6000Stable`.

La V5 n'applique pas automatiquement :

- tensions DDR5 ;
- timings secondaires ;
- FCLK/UCLK manuels ;
- Memory Try It! ;
- High-Efficiency Mode ;
- Latency Killer.

Ces options restent expérimentales et nécessitent une branche dédiée avec benchmark, stress test et rollback.

## 3. BIOS / UEFI MSI

Cible :

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

Le BIOS est inventorié avec sa version et sa date, mais **n'est jamais flashé automatiquement**. La revue d'un BIOS stable MSI reste une preuve manuelle.

## 4. Intel Arc B580

Intel Arc B-Series dépend fortement de ReBAR pour fonctionner dans ses conditions optimales. La V5 exige donc :

```text
UEFI / GPT            OK
CSM                    OFF
Above 4G               ON
Resizable BAR          ON
Arc B580               détectée
Pilote Arc             >= baseline approuvée
1440p / 240 Hz         validé
```

ReBAR n'est pas inventé depuis une API Windows non fiable. Il est vérifié dans l'UEFI puis confirmé dans Intel Graphics Software ou Intel Driver & Support Assistant et enregistré dans la checklist manuelle.

Baseline pilote revue le **2026-08-12** :

```text
Intel Arc B-Series minimum approuvé : 32.0.101.8864
```

Une version plus récente est acceptée. Une version inférieure fait échouer la qualification symbiose.

Aucune mise à jour Intel automatique n'est lancée par le dépôt.

## 5. AMD chipset B850

Baseline revue le **2026-08-12** :

```text
AMD Chipset Software minimum approuvé : 8.05.04.516
```

Le script tente de lire la version du package installé depuis les entrées de désinstallation Windows.

- version détectée et inférieure à la baseline : KO ;
- version détectée et égale/supérieure : OK ;
- version non exposée proprement par Windows : avertissement et preuve manuelle `CurrentVendorDriversReviewed` conservée.

Le dépôt ne télécharge ni n'installe automatiquement une nouvelle version de pilote chipset.

## 6. SSD — 2× Crucial T705

Placement physique attendu :

```text
T705 #1 -> M2_1 CPU PCIe 5.0 x4
T705 #2 -> M2_2 CPU PCIe 5.0 x4
```

La position reste une preuve manuelle, mais Windows vérifie automatiquement :

- au moins deux T705 ;
- bus NVMe ;
- état `Healthy` ;
- `OperationalStatus` ;
- température si exposée ;
- température maximale si exposée ;
- usure ;
- heures de fonctionnement ;
- erreurs lecture/écriture.

Seuils de surveillance V5 :

```text
< 65 °C       normal
65 à 70 °C    warning : vérifier dissipateur et airflow
> 70 °C       KO de qualification
```

La V5 ne lance jamais : Secure Erase, Sanitize, RAID, Momentum Cache, mise à jour firmware ou benchmark d'écriture massif.

## 7. Réseau — 5 GbE + Wi-Fi 7

La carte mère fournit un contrôleur Realtek 8126 5 GbE et du Wi-Fi 7. La qualification vérifie la présence des périphériques et inventorie :

- pilote ;
- date/version du pilote ;
- état des cartes physiques ;
- vitesse de lien lorsqu'elle est disponible ;
- RSS pour l'interface 5 GbE lorsqu'il est exposé.

La vitesse négociée n'est pas imposée à 5 Gbit/s : elle dépend aussi du switch/routeur et du câblage.

La V5 ne désactive jamais automatiquement :

- RSS ;
- checksum offload ;
- Large Send Offload ;
- Receive Segment Coalescing ;
- IPv6 ;
- Energy Efficient Ethernet.

Cela protège les performances réseau, Docker et WSL2 contre les pseudo-tweaks de latence.

## 8. Sécurité matérielle Windows

La qualification existante reste stricte sur :

- GPT ;
- Secure Boot ;
- TPM ;
- virtualisation firmware.

Le module symbiose ajoute l'observation de :

```text
VBS
Memory Integrity / HVCI
```

VBS/HVCI ne sont pas activés automatiquement. Un pilote incompatible doit être identifié avant toute activation afin d'éviter une régression ou un échec de démarrage.

## 9. Plan d'alimentation

Le plan stable reste **Balanced**.

Sont explicitement hors politique :

- Ultimate Performance imposé ;
- minimum CPU 100 % ;
- core parking forcé ;
- C-States désactivés ;
- `useplatformclock` ;
- `disabledynamictick` ;
- autres recettes HPET/BCD non mesurées.

## 10. Inventaires et rapports

Inventaire matériel détaillé :

```powershell
.\scripts\windows\50_hardware_inventory.ps1
```

Rapport :

```text
reports/hardware/hardware-inventory-v5.json
```

Qualification symbiose non mutative :

```powershell
.\scripts\windows\52_hardware_symbiosis.ps1 -Mode Audit
```

Rapport :

```text
reports/hardware/hardware-symbiosis-v5.json
```

Qualification stricte symbiose :

```powershell
.\scripts\windows\52_hardware_symbiosis.ps1 -Mode Verify
```

Verdict attendu :

```text
VERDICT: V5 HARDWARE SYMBIOSIS READY
```

## 11. Qualification V5 automatique complète

```powershell
.\scripts\bootstrap\13_validate_hardware_v5.ps1
```

Elle vérifie désormais :

- Ryzen 7 7700 ;
- 8 cœurs / 16 threads ;
- virtualisation firmware ;
- 48 Go minimum ;
- mémoire à 6000 ;
- MSI B850M Mortar ;
- Arc B580 ;
- baseline pilote Arc ;
- deux T705 sains en NVMe ;
- température T705 non critique ;
- C: et D: NTFS ;
- disque système GPT ;
- Secure Boot ;
- TPM ;
- Balanced ;
- TRIM ;
- 2560×1440 à au moins 239 Hz ;
- Realtek 8126 ;
- Wi-Fi ;
- AMD Chipset Software non inférieur à la baseline lorsqu'il est détectable.

Rapport principal :

```text
reports/hardware/validation-hardware-v5.json
```

## 12. Qualification manuelle

Afficher :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Show
```

Les huit preuves restent :

- UEFI/CSM ;
- Above 4G ;
- ReBAR ;
- T705 en M2_1/M2_2 ;
- refroidissement T705 ;
- stabilité DDR5 6000 ;
- revue BIOS stable ;
- revue des pilotes constructeur.

Exemple :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 `
  -Mode Record `
  -UefiCsmDisabled `
  -Above4GEnabled `
  -ResizableBarEnabled `
  -T705InM2Slots `
  -T705CoolingVerified `
  -Memory6000Stable `
  -LatestStableBiosReviewed `
  -CurrentVendorDriversReviewed
```

Qualification finale :

```powershell
.\scripts\bootstrap\13_validate_hardware_v5.ps1 -RequireManualChecks
```

Verdicts attendus :

```text
VERDICT: V5 HARDWARE SYMBIOSIS READY
VERDICT: V5 HARDWARE MANUAL CHECKS READY
VERDICT: V5 HARDWARE READY
```

## 13. Anti-régression

Le workflow :

```text
.github/workflows/hardware-symbiosis-v5.yml
```

contrôle :

- la baseline AMD/Intel ;
- les seuils T705 ;
- le maintien de Balanced ;
- l'interdiction d'auto-flash BIOS/SSD ;
- l'absence de mutation réseau/sécurité ;
- le câblage du module symbiose dans la qualification V5 ;
- un vrai `Audit` sur runner Windows.

L'objectif n'est pas d'obtenir le score synthétique maximal. L'objectif est une workstation **stable, mesurable, reproductible et performante**, où chaque changement matériel ou pilote peut être qualifié avant de devenir la nouvelle baseline.
