# Qualification matérielle

Ce guide explique comment vérifier que la workstation réelle correspond à l'architecture prévue, sans transformer le dépôt en outil d'overclocking ou de modification automatique du BIOS.

Le projet est volontairement **hardware-aware** : Windows peut démarrer alors que la plateforme ne respecte pas encore les hypothèses matérielles nécessaires à une workstation DevOps/Ops fiable.

## Objectif

La qualification doit répondre à trois questions :

```text
Que peut observer Windows automatiquement ?
Que doit confirmer un humain ?
Qu'est-ce que le dépôt refuse de modifier automatiquement ?
```

## Matériel cible

| Composant | Cible actuelle |
| --- | --- |
| CPU | AMD Ryzen 7 7700 — 8 cœurs / 16 threads |
| Carte mère | MSI MAG B850M Mortar WiFi |
| RAM | 48 Go DDR5 — 6000 MT/s uniquement si la stabilité est démontrée |
| GPU | Intel Arc B580 12 Go |
| SSD système | Crucial T705 PCIe 5.0 |
| SSD DATA / WSL | Crucial T705 PCIe 5.0 |
| Refroidissement | DeepCool LD240WH |
| Alimentation | Corsair RM650e 650 W |
| Boîtier | ASUS Prime AP201 |
| Affichage | 2560×1440 à haut taux de rafraîchissement |

## Modèle de preuve

```text
propriété observable par Windows
        ↓
preuve automatique

propriété firmware / montage / stabilité
        ↓
preuve humaine explicite

mutation sensible ou dangereuse
        ↓
aucune automatisation
```

Le dépôt ne modifie jamais automatiquement :

- le BIOS/UEFI ;
- PBO ou Curve Optimizer ;
- un overclocking CPU/GPU ;
- des timings mémoire ;
- une fréquence DDR5 forcée ;
- ReBAR / Above 4G ;
- un emplacement M.2 ;
- un firmware SSD.

## Vérifications automatiques

La validation peut notamment contrôler :

- modèle CPU et nombre de cœurs/threads ;
- mémoire visible ;
- carte mère ;
- GPU et pilote ;
- présence des SSD et filesystems ;
- GPT ;
- TRIM ;
- Secure Boot ;
- TPM ;
- virtualisation firmware ;
- résolution/fréquence d'affichage observable ;
- plan d'alimentation ;
- VBS/HVCI lorsque disponible ;
- informations NVMe accessibles sans écriture destructive.

Commande principale :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

## Vérifications manuelles

Certaines propriétés ne sont pas démontrables de manière fiable depuis une API Windows générique :

- CSM désactivé ;
- Above 4G Decoding actif ;
- ReBAR actif ;
- SSD installés dans les emplacements M.2 prévus ;
- refroidissement et airflow corrects ;
- stabilité mémoire ;
- revue d'une version BIOS stable ;
- revue des pilotes chipset/GPU/réseau.

Saisie guidée :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Record -Interactive
```

Affichage des contrôles :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Show
```

Si une information obligatoire n'est pas prouvée, le bon verdict est `ACTION REQUISE`.

## Mémoire DDR5

La fréquence de 6000 MT/s n'est pas une obligation supérieure à la stabilité.

```text
6000 MT/s stable > fréquence plus basse
fréquence plus basse stable > 6000 MT/s instable
```

Une workstation DevOps doit privilégier l'intégrité des builds, fichiers et environnements à un gain marginal de performance mémoire.

## Intel Arc B580

Le GPU doit fonctionner dans une plateforme cohérente :

- Above 4G Decoding vérifié ;
- ReBAR vérifié ;
- pilote Intel stable ;
- affichage cible correctement détecté ;
- aucun tweak GPU agressif imposé par le dépôt.

## Crucial T705

Les SSD sont critiques :

```text
C: -> Windows et composants système
E: -> données, WSL2, ISO et exports
```

Les emplacements de projets externes ne font pas partie du contrat de stockage de ce dépôt.

Le projet :

- n'exécute pas de benchmark d'écriture massif automatiquement ;
- conserve TRIM et Scheduled Optimize ;
- privilégie les contrôles de santé et d'identité ;
- vérifie séparément l'identité physique `C:` / `E:` via le parcours V25.

Référence : [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md).

## Plan d'alimentation

Le profil attendu reste **Balanced**. Le projet cherche une machine réactive et efficace, pas un mode « performances maximales » imposé en permanence.

Voir [`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md).

## Quand refaire la qualification ?

Relancez-la après :

- mise à jour BIOS importante ;
- changement de pilote chipset ou GPU ;
- remplacement d'un SSD ;
- changement de RAM ou de fréquence mémoire ;
- modification UEFI liée à la virtualisation ou au GPU ;
- instabilité inexpliquée ;
- réinstallation complète de Windows.

## Critère de réussite

```text
inventaire automatique cohérent
+ preuves manuelles renseignées
+ identité du stockage vérifiée
+ aucune erreur bloquante
+ aucune instabilité connue
```

La CI peut vérifier le code et les contrats, mais elle ne peut pas certifier le matériel physique. La qualification finale doit être exécutée sur la workstation réelle.
