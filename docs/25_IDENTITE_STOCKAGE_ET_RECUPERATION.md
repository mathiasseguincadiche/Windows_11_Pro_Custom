# Identité du stockage et reprise après disparition d'un volume

Ce document définit le garde-fou identité stockage imposé par les parcours stricts de `install.ps1` et par le bootstrap WSL avant leurs mutations.
Il répond à deux risques différents :

- une lettre `C:` ou `E:` peut désigner un autre volume après un redémarrage ;
- un volume peut être présent physiquement mais ne plus être monté, être hors ligne,
  verrouillé ou absent de la table de partitions.

identité stockage ne crée, ne supprime, ne formate, ne redimensionne et ne répare aucune
partition. Il observe la topologie et bloque l'installation si l'identité réelle
ne correspond plus à la référence explicitement approuvée.

## Portée d'application

Le contrôle est appelé automatiquement par le préflight strict de `install.ps1`
en modes `Apply` et `Verify`, puis directement par le bootstrap WSL avant toute
création ou modification de son emplacement.

Les scripts internes exécutés isolément restent des composants ciblés : leur
succès ne constitue pas une preuve de conformité globale. Avant un `Apply` direct,
exécuter explicitement identité stockage puis jalon historique, ou préférer le parcours orchestré.

## Identités contrôlées

Pour les rôles `C:` et `E:`, le contrat enregistre puis vérifie :

- le numéro de série et l'`UniqueId` du disque physique ;
- le GUID et l'`UniqueId` de la partition ;
- le `VolumeUniqueId` Windows ;
- la lettre, le filesystem, la taille et les indicateurs boot/system ;
- la présence de `C:` et `E:` sur deux disques physiques distincts ;
- pour `E:`, un type GPT de partition de données (`Basic data`) et jamais une partition EFI/MSR/Recovery déguisée.

La baseline locale, indépendante du checkout Git et conservée sur le volume
système, se trouve dans :

```text
%ProgramData%\Windows11ProCustom\storage-v25\volume-identity.json
```

Elle n'est jamais publiée dans Git car elle contient l'identité physique de la
machine. Le Golden Backup en conserve une copie contrôlée et son SHA-256 dans les
métadonnées de la session, en plus de l'image Windows qui protège `C:`.

## Premier enrôlement sur une machine saine

Avant la première installation complète, ouvrir PowerShell en administrateur et
produire d'abord l'inventaire :

```powershell
.\scripts\bootstrap\00_storage_identity.ps1 -Mode Audit
```

Contrôler dans la Gestion des disques et dans le rapport
`reports\storage-identity-v25\latest-topology.json` que :

- `C:` est bien le volume Windows attendu ;
- `E:` est bien le second SSD destiné aux données et à WSL ;
- les deux volumes sont NTFS, GPT, sains et situés sur deux SSD distincts ;
- `E:` est une partition GPT de données normale (`Basic data`) ;
- `E:` n'est ni boot, ni système, ni masqué.

Après cette vérification humaine seulement :

```powershell
.\scripts\bootstrap\00_storage_identity.ps1 `
  -Mode Record `
  -ConfirmHealthyTopology
```

Puis prouver immédiatement la correspondance :

```powershell
.\scripts\bootstrap\00_storage_identity.ps1 -Mode Verify
```

L'installation complète restera bloquée tant que cette preuve n'est pas valide.

## Remplacement de la baseline

Une baseline existante n'est jamais remplacée automatiquement. Après changement
physique volontaire d'un SSD ou recréation contrôlée d'une partition, effectuer
une nouvelle investigation, puis utiliser explicitement les deux confirmations :

```powershell
.\scripts\bootstrap\00_storage_identity.ps1 `
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
.\scripts\bootstrap\00_storage_identity.ps1 -Mode Audit
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

L'option WSL `--location E:\WSL\Ubuntu-DevOps` désigne un dossier dans le volume
NTFS `E:`. Elle ne crée pas de partition Linux physique. Le script WSL appelle
désormais identité stockage en mode `Verify` avant toute création de dossier, mise à jour WSL
ou installation de distribution.

## Intégrité locale de la baseline

La baseline locale identité stockage est désormais accompagnée d'un sidecar SHA-256 :

```text
%ProgramData%\Windows11ProCustom\storage-v25\volume-identity.json.sha256
```

En mode `Verify`, une baseline sans sidecar valide est refusée. Après migration
d'une ancienne baseline ou après réinvestigation d'une topologie saine, relancer
explicitement l'enrôlement `-Mode Record -ConfirmHealthyTopology` pour régénérer
la paire JSON + SHA-256 locale.
