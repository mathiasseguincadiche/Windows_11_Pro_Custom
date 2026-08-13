# Stockage — architecture et règles

## Règle absolue

Les deux SSD internes Crucial T705 restent en **NTFS**.

| Disque | Lettre | Filesystem | Rôle principal |
|---|---|---|---|
| Crucial T705 #1 | `C:` | NTFS | Windows 11 Pro, applications, profils |
| Crucial T705 #2 | `D:` | NTFS | DATA, WSL2 VHDX, OpenClaw, ISO, données lourdes |
| Disque externe séparé | exemple `E:` | NTFS | Golden Backup V7 |

Aucune commande du dépôt ne doit formater automatiquement un disque.

---

## Pourquoi pas de partition EXT4 physique ?

WSL2 stocke le filesystem Linux dans un disque virtuel VHDX :

```text
D: NTFS
└── D:\WSL\Ubuntu-DevOps\...
    └── VHDX WSL
        └── filesystem ext4 Ubuntu
```

Le second T705 ne doit donc pas être transformé en disque Linux physique.

---

## Arborescence logique de `D:`

```text
D:\
├── DATA\
├── WSL\
│   ├── Ubuntu-DevOps\
│   └── swap\
├── AI\
│   └── OpenClaw\
├── ISO\
└── EXPORTS\
```

Les dossiers exacts peuvent évoluer selon les besoins, mais les emplacements contractuels sont notamment :

```text
D:\WSL\Ubuntu-DevOps
D:\WSL\swap\wsl-swap.vhdx
D:\AI\OpenClaw
```

---

## `D:\BACKUPS` n'est pas le Golden Backup

Un dossier de travail ou un export temporaire sur `D:` peut être utile, mais **il ne protège pas contre la panne du T705 #2**.

Le Golden Backup V7 doit utiliser un autre disque physique, USB NTFS par défaut :

```text
E:\
├── WindowsImageBackup\
└── Windows_11_Pro_Custom_Backup\V7\...
```

La politique V7 protège `C:` **et** `D:` ; la cible ne peut donc pas être un de ces mêmes disques.

---

## WSL2

La distribution cible est :

```text
Ubuntu 26.04
D:\WSL\Ubuntu-DevOps
```

Les projets Linux restent **dans le filesystem ext4 du VHDX**, par exemple :

```text
/home/<user>/projects
/home/<user>/labs
/home/<user>/repositories
```

Ils ne doivent pas être déplacés sous `/mnt/c` ou `/mnt/d` comme emplacement de travail principal.

---

## Vérifier C: et D:

PowerShell :

```powershell
Get-Volume -DriveLetter C,D |
    Format-Table DriveLetter,FileSystem,FileSystemLabel,HealthStatus,Size,SizeRemaining
```

Attendu :

```text
C: NTFS Healthy
D: NTFS Healthy
```

Vérifier la table de partitions et les modèles de disques :

```powershell
Get-Disk |
    Format-Table Number,FriendlyName,PartitionStyle,HealthStatus,OperationalStatus,Size
```

Le disque système doit être GPT.

---

## TRIM / ReTrim

Audit :

```powershell
.\scripts\windows\21_storage_trim.ps1 -Mode Audit
```

Application manuelle si réellement nécessaire :

```powershell
.\scripts\windows\21_storage_trim.ps1 -Mode Apply
```

Le dépôt ne désactive pas la planification Windows d'optimisation des SSD.

---

## Installation Windows : éviter le mauvais T705

Les deux SSD étant similaires, la méthode la plus sûre lors d'une réinstallation complète est de désactiver/déconnecter temporairement le SSD destiné à `D:` si cela est simple et sûr, puis de le reconnecter après le premier boot Windows.

Voir [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) pour la procédure détaillée.

---

## Sauvegarde

Voir :

- [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) — vue courte ;
- [`18_BACKUP_DISASTER_RECOVERY_V7.md`](18_BACKUP_DISASTER_RECOVERY_V7.md) — procédure complète.
