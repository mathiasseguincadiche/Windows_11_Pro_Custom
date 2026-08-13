# Stockage — architecture et règles

## Règle absolue

Les deux SSD internes Crucial T705 restent en **NTFS**.

| Disque | Lettre | Filesystem | Rôle principal |
| --- | --- | --- | --- |
| Crucial T705 #1 | `C:` | NTFS | Windows 11 Pro, applications, profils |
| Crucial T705 #2 | `D:` | NTFS | données, WSL2 VHDX, OpenClaw, ISO, données lourdes |
| Disque externe séparé | exemple `E:` | NTFS | sauvegarde de référence |

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

Cette architecture garde :

- Windows maître des deux SSD physiques ;
- Ubuntu sur un vrai filesystem Linux ;
- pas de dual boot ;
- export/import WSL indépendant ;
- une stratégie de sauvegarde cohérente de `C:` et `D:`.

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

Les emplacements contractuels importants sont notamment :

```text
D:\WSL\Ubuntu-DevOps
D:\WSL\swap\wsl-swap.vhdx
D:\AI\OpenClaw
```

OpenClaw est optionnel ; `D:\AI` peut rester absent tant que cette intégration n'est pas utilisée.

---

## `D:\BACKUPS` n'est pas une sauvegarde externe suffisante

Un export temporaire sur `D:` peut être utile, mais **il ne protège pas contre la panne du T705 #2**.

La sauvegarde de référence doit vivre sur un autre disque physique, typiquement un support USB NTFS :

```text
E:\
├── WindowsImageBackup\
└── sauvegarde WSL / manifest / hashes
```

Puisque `C:` et `D:` font partie de ce qui doit être protégé, aucun de ces deux volumes ne peut constituer à lui seul la cible de reprise complète.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

## WSL2

La distribution cible actuelle est :

```text
Ubuntu 26.04
D:\WSL\Ubuntu-DevOps
```

Les projets Linux restent **dans le filesystem ext4 du VHDX** :

```text
/home/<user>/projects
/home/<user>/labs
/home/<user>/repositories
```

Ils ne doivent pas être déplacés sous `/mnt/c` ou `/mnt/d` comme emplacement de travail principal.

Guide : [`06_WSL2.md`](06_WSL2.md).

---

## Vérifier `C:` et `D:`

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

Application si une correction est réellement nécessaire :

```powershell
.\scripts\windows\21_storage_trim.ps1 -Mode Apply
```

Le dépôt ne désactive pas la planification Windows d'optimisation des SSD.

Il évite aussi les benchmarks synthétiques provoquant de gros volumes d'écriture inutiles sur les T705.

---

## Espace libre

Un SSD très rempli finit par perdre en souplesse opérationnelle, notamment pour :

- Windows Update ;
- WSL2/VHDX ;
- images Docker ;
- builds ;
- caches ;
- sauvegardes temporaires.

Le projet préfère surveiller l'espace libre et nettoyer les données réellement identifiées plutôt qu'utiliser un outil de « nettoyage magique ».

---

## Installation Windows : éviter le mauvais T705

Les deux SSD étant similaires, la méthode la plus sûre lors d'une réinstallation complète est de désactiver ou déconnecter temporairement le SSD destiné à `D:` si cela est simple et sans risque, puis de le reconnecter après le premier démarrage Windows.

Voir [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md).

---

## Remplacement d'un SSD

En cas de remplacement :

1. identifier clairement le rôle du nouveau disque ;
2. vérifier GPT/NTFS ;
3. ne jamais réutiliser une ancienne lettre de lecteur sans vérifier les données présentes ;
4. restaurer uniquement depuis une sauvegarde validée ;
5. requalifier le stockage et le matériel après intervention.

Pour une reconstruction complète : [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md).

---

## Résumé

```text
C: NTFS -> système Windows
D: NTFS -> données + WSL2 + intégrations lourdes
VHDX    -> ext4 Linux interne
USB     -> sauvegarde de référence externe
```

Cette séparation permet de conserver les avantages d'un poste Windows classique et d'un environnement Linux performant sans multiplier les partitions ni les systèmes de démarrage.
