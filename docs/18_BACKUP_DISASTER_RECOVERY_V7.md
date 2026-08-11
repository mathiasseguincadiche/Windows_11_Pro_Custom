# V7 — Backup & Disaster Recovery

## Objectif

La V7 protège l'état réel du poste après qualification V1 à V6.

Elle complète la reproductibilité GitHub avec trois niveaux de récupération :

1. **System Restore** pour une régression Windows légère ;
2. **export WSL2 VHDX** pour restaurer Ubuntu indépendamment ;
3. **image Windows complète** de `C:` + `D:` + volumes critiques pour une récupération bare-metal.

La règle de sécurité V7 est stricte :

```text
sauvegarder automatiquement : OUI
vérifier automatiquement   : OUI
générer un plan de reprise  : OUI
restaurer automatiquement   : NON
reformater automatiquement  : NON
wsl --unregister auto       : INTERDIT
```

## Architecture protégée

```text
Crucial T705 #1
└── C: NTFS
    ├── Windows 11 Pro
    ├── applications
    ├── pilotes
    ├── configuration
    └── profils utilisateur

Crucial T705 #2
└── D: NTFS
    ├── DATA
    ├── D:\WSL\Ubuntu-DevOps\ext4.vhdx
    └── D:\WSL\swap\wsl-swap.vhdx

Disque de sauvegarde séparé
└── E: NTFS (exemple)
    ├── WindowsImageBackup\
    └── Windows_11_Pro_Custom_Backup\V7\<timestamp>\
        ├── WSL\
        │   ├── Ubuntu-GOLDEN-V7.vhdx
        │   └── SHA256.txt
        └── metadata\
            ├── backup-manifest.json
            ├── winre-info.txt
            ├── restore-point.txt
            ├── wbadmin-start-backup.txt
            └── wbadmin-get-versions.txt
```

Le disque de sauvegarde doit être un **autre disque physique** que ceux qui hébergent `C:` et `D:`.

Par défaut, la V7 exige un disque dont Windows détecte `BusType=USB`. Un troisième disque non USB reste possible uniquement avec l'option explicite `-AllowNonUsbBackupTarget` après vérification humaine.

## Politique versionnée

La politique se trouve dans :

```text
config/backup/v7-policy.json
```

Valeurs importantes :

- volumes protégés : `C:` et `D:` ;
- espace libre minimum avant lancement : 100 Go ;
- cible USB exigée par défaut ;
- export WSL en VHDX ;
- SHA-256 obligatoire ;
- distribution de test de restauration différente de la distribution active ;
- restauration destructive automatisée : `false`.

## Préparation initiale

### 1. Brancher le disque de sauvegarde

Exemple :

```text
E:
```

Il doit être en NTFS et distinct physiquement des deux T705 protégés.

### 2. Ouvrir PowerShell en administrateur

PowerShell 7 est recommandé :

```powershell
pwsh
```

### 3. Auditer WinRE

```powershell
reagentc /info
```

La V7 refuse de créer le Golden Backup si Windows Recovery Environment n'est pas confirmé comme actif.

## Création du Golden Backup V7

Commande principale :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
```

La séquence est :

```text
contrôle administrateur
      ↓
contrôle E: NTFS
      ↓
contrôle disque physique séparé de C: et D:
      ↓
contrôle cible USB par défaut
      ↓
contrôle espace libre
      ↓
contrôle Ubuntu présent
      ↓
contrôle WinRE actif
      ↓
tentative de point de restauration Windows
      ↓
wsl --shutdown
      ↓
wbadmin image C: + D: + volumes critiques
      ↓
wbadmin get versions
      ↓
wsl --export Ubuntu ... --vhd
      ↓
SHA-256 du VHDX
      ↓
manifest JSON
```

Le premier `wbadmin start backup` reste interactif : aucune option `-quiet` n'est ajoutée. L'opérateur voit donc la demande de confirmation de Windows.

Verdict de création attendu :

```text
VERDICT: V7 GOLDEN BACKUP CREATED
```

### Cible non USB

Uniquement si le disque a été vérifié comme réellement séparé :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E: -AllowNonUsbBackupTarget
```

Cette option ne permet jamais d'utiliser un disque qui héberge déjà `C:` ou `D:`.

### Point de restauration

La création du point de restauration est tentée via Windows PowerShell 5.1 pour conserver la compatibilité de `Checkpoint-Computer`.

Windows limite `Checkpoint-Computer` à un point créé par jour. Un échec lié à cette limite n'annule donc pas l'image système V7.

Pour ignorer volontairement cette tentative :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E: -SkipBackupRestorePoint
```

## Vérification du Golden Backup

Une sauvegarde n'est considérée utilisable qu'après vérification :

```powershell
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
```

Le validateur exige :

- `WindowsImageBackup` présent ;
- au moins une version récupérable énumérée par `wbadmin get versions` ;
- WinRE actif ;
- manifest V7 présent ;
- VHDX WSL présent ;
- SHA-256 du VHDX identique au manifest ;
- politique destructive toujours désactivée.

Rapport :

```text
reports/backup/validation-v7.json
```

Verdict attendu :

```text
VERDICT: V7 BACKUP READY
```

## Restauration WSL2 uniquement

La V7 ne remplace jamais directement la distribution active.

Générer le plan :

```powershell
.\install.ps1 -BackupAction RestorePlan -BackupTargetDrive E:
```

Le principe est :

```text
Ubuntu actuel
   │
   ├── reste intact
   │
   └── Ubuntu-Restore-V7 importé à côté
              ↓
         vérification
              ↓
HOME / projects / Docker / Terraform / kubectl / etc.
              ↓
       décision humaine seulement
```

Le plan propose une commande de ce type :

```powershell
wsl --shutdown
wsl --import Ubuntu-Restore-V7 "D:\WSL\Ubuntu-Restore-V7" "E:\...\Ubuntu-GOLDEN-V7.vhdx" --vhd
wsl -l -v
wsl -d Ubuntu-Restore-V7
```

**Aucun `wsl --unregister Ubuntu` n'est exécuté ou recommandé avant validation de la copie restaurée.** Cette commande supprime définitivement les données de la distribution ciblée.

## Régression Windows légère

Pour un mauvais pilote, tweak ou logiciel :

```text
Paramètres de récupération / Windows RE
      ↓
System Restore
      ↓
point Windows_11_Pro_Custom V7 Golden Backup
```

Le point de restauration est un filet de sécurité rapide ; il ne remplace pas l'image complète.

## Récupération Windows bare-metal

Scénario : Windows ne démarre plus, SSD remplacé, partitions endommagées ou récupération totale nécessaire.

### Étape 1 — démarrer WinRE

Utiliser :

- l'environnement Windows Recovery Environment installé ; ou
- une clé Recovery Drive créée auparavant.

### Étape 2 — connecter le disque Golden Backup

Exemple : `E:` dans l'environnement de récupération. La lettre peut changer dans WinRE ; elle doit être vérifiée avant toute commande.

### Étape 3 — lister les versions disponibles

```text
wbadmin get versions -backupTarget:E:
```

### Étape 4 — sélectionner explicitement la bonne version

La V7 génère un modèle de commande mais **ne l'exécute pas** :

```text
wbadmin start sysrecovery -version:<VERSION_IDENTIFIER> -backupTarget:E: -restoreAllVolumes
```

Cette commande doit être lancée manuellement depuis la console WinRE après vérification des disques.

L'option `-recreateDisks` n'est jamais ajoutée automatiquement. Elle peut repartitionner les disques et n'est acceptable qu'après une décision humaine explicite sur un scénario de remplacement de stockage.

## Recovery Drive

Créer périodiquement une clé dédiée :

```powershell
recoverydrive.exe
```

La création est volontairement interactive car Windows efface la clé USB sélectionnée.

Microsoft recommande de recréer le support de récupération périodiquement pour intégrer les mises à jour récentes. Ce support n'est pas une sauvegarde des fichiers personnels ; il complète le Golden Backup.

## Plan de restauration offline

Génération :

```powershell
.\install.ps1 -BackupAction RestorePlan -BackupTargetDrive E:
```

Fichier produit :

```text
reports/backup/restore-plan-v7.txt
```

Le script :

- recalcule le SHA-256 du VHDX avant de produire le plan ;
- bloque si l'intégrité WSL est incorrecte ;
- utilise un nom de distribution de restauration distinct ;
- fournit les étapes WSL et WinRE ;
- n'exécute aucune restauration.

## Cycle recommandé

### Golden V7

Créer une première image une fois la V6 réellement qualifiée sur la machine :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware -ValidateWsl -ValidateDevOps
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
```

### Nouveaux snapshots

Créer un nouveau Golden Backup après un changement majeur et stabilisé :

- grosse mise à niveau Windows ;
- changement important de pilotes ;
- évolution structurante WSL2 ;
- changement majeur de la stack DevOps ;
- avant une opération système risquée.

Ne pas supprimer immédiatement le précédent snapshot validé.

## Ordre de reprise

```text
Incident mineur Windows
→ System Restore

WSL uniquement
→ VHDX exporté
→ import sous un autre nom
→ validation

Windows / disque système
→ WinRE
→ WindowsImageBackup
→ bare-metal recovery

Perte complète des sauvegardes locales
→ Windows propre
→ GitHub Windows_11_Pro_Custom
→ reconstruction V1 à V7
```

## Sources Microsoft vérifiées le 11 août 2026

- Microsoft Learn — `wbadmin start backup` : Windows 11 est pris en charge ; `-allCritical` inclut les volumes critiques et peut être combiné avec `-include`.
- Microsoft Learn — `wbadmin get versions` : énumère les sauvegardes et les types de récupération disponibles.
- Microsoft Learn — `wbadmin start sysrecovery` : récupération bare-metal et exécution depuis Windows Recovery Console.
- Microsoft Learn — `reagentc /info` : vérification de l'état de Windows RE.
- Microsoft Learn — commandes WSL : `wsl --export ... --vhd`, `wsl --import ... --vhd` et avertissement destructif pour `wsl --unregister`.
- Microsoft Support — Recovery Drive : support de récupération bootable, clé USB effacée lors de sa création et absence de sauvegarde des fichiers personnels.

## Verdict V7

La V7 est considérée prête uniquement après une vraie sauvegarde sur la machine et :

```text
VERDICT: V7 BACKUP READY
```

La CI GitHub peut qualifier le code et les garde-fous, mais elle ne peut pas prétendre qu'une image réelle de `C:` / `D:` ou un export de l'Ubuntu réel existe.
