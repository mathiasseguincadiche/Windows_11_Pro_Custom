# Stockage — architecture et règles

## Règle absolue

Les deux SSD internes Crucial T705 restent en **NTFS**.

| Disque | Lettre | Filesystem | Rôle principal |
| --- | --- | --- | --- |
| Crucial T705 #1 | `C:` | NTFS | Windows 11 Pro, applications, profils |
| Crucial T705 #2 | `D:` | NTFS | données, WSL2 VHDX, ISO, données lourdes |
| Disque externe séparé | exemple `E:` | NTFS | sauvegarde de référence |

Aucune commande du dépôt ne doit formater automatiquement un disque.

## WSL2 et ext4

```text
D: NTFS
└── D:\WSL\Ubuntu-DevOps\...
    └── VHDX WSL
        └── filesystem ext4 Ubuntu
```

Le second T705 reste donc un disque Windows NTFS ; le filesystem Linux vit dans le VHDX WSL2.

## Arborescence logique de `D:`

```text
D:\
├── DATA\
├── WSL\
│   ├── Ubuntu-DevOps\
│   └── swap\
├── ISO\
└── EXPORTS\
```

Les emplacements contractuels du dépôt sont :

```text
D:\WSL\Ubuntu-DevOps
D:\WSL\swap\wsl-swap.vhdx
```

Les dossiers appartenant à des projets externes ne font pas partie du contrat de stockage de `Windows_11_Pro_Custom`.

## Sauvegarde externe

`D:\BACKUPS` ne protège pas contre une panne de `D:`. La sauvegarde de référence doit vivre sur un autre disque physique, typiquement un support USB NTFS.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

## Projets Linux

```text
/home/<user>/projects
/home/<user>/labs
/home/<user>/repositories
```

Ils restent dans le filesystem Linux et non sous `/mnt/c` ou `/mnt/d` comme racines de travail principales.

## Vérifications

```powershell
Get-Volume -DriveLetter C,D |
    Format-Table DriveLetter,FileSystem,FileSystemLabel,HealthStatus,Size,SizeRemaining
```

Attendu : `C:` et `D:` en NTFS et sains.

```powershell
Get-Disk |
    Format-Table Number,FriendlyName,PartitionStyle,HealthStatus,OperationalStatus,Size
```

Le disque système doit être GPT.

## TRIM / ReTrim

```powershell
.\scripts\windows\21_storage_trim.ps1 -Mode Audit
.\scripts\windows\21_storage_trim.ps1 -Mode Apply
```

Le dépôt conserve la planification Windows d'optimisation des SSD et évite les benchmarks générant des écritures inutiles.

## Résumé

```text
C: NTFS -> système Windows
D: NTFS -> données + WSL2 + données lourdes de la workstation
VHDX    -> ext4 Linux interne
USB     -> sauvegarde de référence externe
```

Les projets externes restent libres d'utiliser `D:` mais ne deviennent pas pour autant des composants gérés par ce dépôt.
