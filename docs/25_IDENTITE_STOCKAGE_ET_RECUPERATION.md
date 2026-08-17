# Identité du stockage et reprise après disparition d'un volume

Ce document définit le garde-fou V25 utilisé avant toute convergence Windows/WSL.
Il répond à deux risques différents :

- une lettre `C:` ou `D:` peut désigner un autre volume après un redémarrage ;
- un volume peut être présent physiquement mais ne plus être monté, être hors ligne,
  verrouillé ou absent de la table de partitions.

V25 ne crée, ne supprime, ne formate, ne redimensionne et ne répare aucune
partition. Il observe la topologie et bloque l'installation si l'identité réelle
ne correspond plus à la référence explicitement approuvée.

## Identités contrôlées

Pour les rôles `C:` et `D:`, le contrat enregistre puis vérifie :

- le numéro de série et l'`UniqueId` du disque physique ;
- le GUID et l'`UniqueId` de la partition ;
- le `VolumeUniqueId` Windows ;
- la lettre, le filesystem, la taille et les indicateurs boot/system ;
- la présence de `C:` et `D:` sur deux disques physiques distincts.

La baseline locale se trouve dans :

```text
state\storage-v25\volume-identity.json
```

`state/` est volontairement exclu de Git car il contient l'identité physique de
la machine. La sauvegarde opérationnelle de la workstation doit conserver ce
fichier avec les autres états locaux.

## Premier enrôlement sur une machine saine

Avant la première installation complète, ouvrir PowerShell en administrateur et
produire d'abord l'inventaire :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Audit
```

Contrôler dans la Gestion des disques et dans le rapport
`reports\storage-identity-v25\latest-topology.json` que :

- `C:` est bien le volume Windows attendu ;
- `D:` est bien le second Crucial T705 destiné aux données et à WSL ;
- les deux volumes sont NTFS, GPT, sains et situés sur deux SSD distincts ;
- `D:` n'est ni boot, ni système, ni masqué.

Après cette vérification humaine seulement :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 `
  -Mode Record `
  -ConfirmHealthyTopology
```

Puis prouver immédiatement la correspondance :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Verify
```

L'installation complète restera bloquée tant que cette preuve n'est pas valide.

## Remplacement de la baseline

Une baseline existante n'est jamais remplacée automatiquement. Après changement
physique volontaire d'un SSD ou recréation contrôlée d'une partition, effectuer
une nouvelle investigation, puis utiliser explicitement les deux confirmations :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 `
  -Mode Record `
  -ConfirmHealthyTopology `
  -ReplaceBaseline
```

Ne jamais utiliser cette commande pour faire disparaître une alerte inexpliquée.

## Si un volume disparaît

Arrêter immédiatement les installations et éviter toute écriture sur le SSD.
Ne pas initialiser, formater ou recréer une partition et ne pas lancer
`chkdsk /f`, `diskpart clean`, `ntfsfix` ou une réparation TestDisk avec écriture.

Produire uniquement le rapport non mutatif :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Audit
```

Compléter avec :

```powershell
Get-Disk | Format-Table Number,FriendlyName,SerialNumber,UniqueId,HealthStatus,PartitionStyle,IsOffline,IsReadOnly,Size -AutoSize
Get-Partition | Format-Table DiskNumber,PartitionNumber,DriveLetter,Guid,Type,GptType,IsBoot,IsSystem,IsHidden,Size -AutoSize
Get-Volume | Format-Table DriveLetter,FileSystemLabel,FileSystem,UniqueId,HealthStatus,Size,SizeRemaining -AutoSize
manage-bde -status
```

Interprétation :

| Observation | Signification probable |
| --- | --- |
| partition présente sans lettre | point de montage/lettre perdu ou modifié |
| volume présent mais inaccessible | BitLocker, hors ligne, lecture seule ou NTFS dégradé |
| Windows absent du boot mais partition présente | entrée EFI/Windows Boot Manager à investiguer |
| ancien espace affiché non alloué | entrée GPT perdue ou endommagée ; cloner avant récupération |
| SSD absent ou erreurs NVMe | incident matériel, firmware, alimentation ou contrôleur |

Si l'espace est réellement non alloué, effectuer d'abord une image secteur par
secteur vers un support distinct et de capacité suffisante. Le choix précis de la
source et de la destination doit être validé avant toute commande de clonage.

## Relation avec WSL2

L'option WSL `--location D:\WSL\Ubuntu-DevOps` désigne un dossier dans le volume
NTFS `D:`. Elle ne crée pas de partition Linux physique. Le script WSL appelle
désormais V25 en mode `Verify` avant toute création de dossier, mise à jour WSL
ou installation de distribution.
