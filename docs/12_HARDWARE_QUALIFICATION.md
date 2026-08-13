# Qualification matérielle

Ce guide décrit **comment vérifier que la workstation réelle correspond bien à l'architecture prévue**, sans transformer le dépôt en outil d'overclocking ou de modification automatique du BIOS.

Le projet est volontairement matériel-aware : il ne suffit pas que Windows démarre. La plateforme doit être cohérente avec le CPU, la mémoire, le GPU, les SSD, la virtualisation et les besoins DevOps/gaming de la machine cible.

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

## Philosophie

La qualification suit trois règles :

```text
ce que Windows peut observer
        ↓
preuve automatique

ce qui dépend du firmware ou du montage physique
        ↓
preuve humaine explicite

ce qui pourrait être dangereux à modifier automatiquement
        ↓
aucune mutation
```

Le dépôt **n'applique jamais automatiquement** :

- un flash BIOS/UEFI ;
- PBO ou Curve Optimizer ;
- un overclocking CPU/GPU ;
- des timings mémoire ;
- une fréquence DDR5 forcée ;
- ReBAR / Above 4G ;
- un changement de slot M.2 ;
- un firmware SSD ;
- des réglages réseau agressifs ou non mesurés.

## Vérifications automatiques

La validation matérielle peut contrôler notamment :

- modèle CPU et nombre de cœurs/threads ;
- mémoire visible par Windows ;
- carte mère ;
- GPU et pilote ;
- présence des SSD et filesystems ;
- GPT ;
- état TRIM ;
- Secure Boot ;
- TPM ;
- virtualisation firmware ;
- résolution / fréquence d'affichage observable ;
- plan d'alimentation Windows ;
- état VBS/HVCI lorsque disponible ;
- informations NVMe accessibles sans écriture destructive.

Commande principale :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

## Vérifications manuelles

Certaines propriétés ne sont pas démontrables de façon fiable par une API Windows générique. Le projet les traite donc comme des **preuves manuelles**, pas comme des suppositions :

- CSM désactivé ;
- Above 4G Decoding actif ;
- ReBAR actif ;
- SSD installés dans les emplacements M.2 prévus ;
- refroidissement et airflow corrects ;
- stabilité mémoire à la fréquence retenue ;
- revue d'une version BIOS stable ;
- revue des pilotes chipset/GPU/réseau installés.

Assistant de saisie :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Record -Interactive
```

Pour simplement afficher les contrôles :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Show
```

## Mémoire DDR5

Le projet ne considère pas « 6000 MT/s » comme une obligation absolue. La règle est :

```text
6000 stable > fréquence plus basse
fréquence plus basse stable > 6000 instable
```

Une workstation DevOps doit privilégier la fiabilité : corruption de fichiers, crashs WSL, builds incohérents ou erreurs Terraform/Ansible coûtent beaucoup plus cher qu'un gain marginal de bande passante mémoire.

## Intel Arc B580

Le GPU doit être utilisé avec une plateforme cohérente :

- Above 4G Decoding vérifié ;
- ReBAR vérifié ;
- pilote Intel actuel et stable ;
- affichage cible correctement détecté ;
- aucun tweak GPU agressif appliqué automatiquement.

Le dépôt qualifie l'environnement ; il ne remplace pas la validation UEFI et le contrôle du pilote Intel.

## Crucial T705

Les SSD sont traités comme des composants critiques de la workstation :

- `C:` pour Windows et les applications ;
- `D:` pour les données, WSL2, OpenClaw, ISO et exports ;
- aucun benchmark d'écriture massif exécuté automatiquement ;
- TRIM et Scheduled Optimize Windows restent actifs ;
- le dépôt préfère les contrôles de santé et de cohérence aux pseudo-optimisations SSD.

## Plan d'alimentation

Le profil attendu reste **Balanced**. Le projet cherche une machine réactive et efficace, pas un mode « performances maximales » permanent imposé à l'ensemble du système.

Les optimisations de réactivité sont traitées dans [`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md).

## Quand refaire la qualification ?

Relancer une qualification après :

- mise à jour BIOS importante ;
- changement de pilote chipset ou GPU ;
- remplacement d'un SSD ;
- changement de RAM ou de fréquence mémoire ;
- modification UEFI liée à la virtualisation ou au GPU ;
- instabilité inexpliquée ;
- réinstallation complète de Windows.

## Ce qu'est un résultat fiable

Un résultat fiable combine :

```text
inventaire automatique cohérent
+
preuves manuelles renseignées
+
aucune erreur bloquante
+
aucune instabilité connue
```

La CI GitHub peut vérifier la structure des scripts et des politiques, mais **elle ne peut pas certifier le matériel physique de la machine**. La qualification finale doit donc toujours être exécutée sur la workstation réelle.
