# Sauvegarde et restauration — vue d'ensemble

Ce fichier donne la version courte de la stratégie de protection.

Pour la procédure complète, utiliser :

[`18_BACKUP_DISASTER_RECOVERY_V7.md`](18_BACKUP_DISASTER_RECOVERY_V7.md)

Pour reconstruire la machine après incident :

[`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md)

---

## 1. Ce que GitHub protège — et ne protège pas

Le dépôt GitHub protège :

- scripts ;
- configurations ;
- manifests ;
- documentation ;
- historique du code.

Il ne remplace pas une sauvegarde de :

- Windows réel ;
- `C:` ;
- données de `D:` ;
- profil utilisateur ;
- VHDX WSL réel ;
- données OpenClaw ;
- fichiers locaux non commités ;
- credentials.

---

## 2. Stratégie V7

```text
System Restore
      ↓
régression Windows légère

WindowsImageBackup
      ↓
C: + D: + volumes critiques

WSL export VHDX + SHA-256
      ↓
Ubuntu restaurable séparément

GitHub
      ↓
reconstruction si les sauvegardes locales sont perdues
```

La politique machine-readable se trouve dans :

```text
config/backup/v7-policy.json
```

---

## 3. Cible de sauvegarde

La cible recommandée est un **disque USB NTFS physiquement distinct** des deux Crucial T705.

Politique actuelle :

```text
C: protégé                         OUI
D: protégé                         OUI
cible USB par défaut               OUI
minimum libre avant lancement      100 Go
WSL export                         VHDX
hash                               SHA-256
restore destructif automatique     NON
```

Un dossier `D:\BACKUPS` sur le SSD interne ne constitue pas un Golden Backup V7 suffisant pour protéger ce même disque `D:`.

---

## 4. Créer une sauvegarde

Exemple avec disque USB `E:` :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
```

La V7 :

1. vérifie la cible ;
2. refuse le même disque physique que `C:` / `D:` ;
3. contrôle NTFS / espace libre / USB ;
4. vérifie WinRE ;
5. tente un point de restauration ;
6. arrête WSL ;
7. crée l'image Windows ;
8. exporte Ubuntu en VHDX ;
9. calcule SHA-256 ;
10. écrit le manifest.

---

## 5. Vérifier la sauvegarde

```powershell
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
```

Verdict attendu après une **vraie sauvegarde** :

```text
VERDICT: V7 BACKUP READY
```

Une sauvegarde non vérifiée ne doit pas être considérée comme un plan de reprise fiable.

---

## 6. Préparer une restauration

```powershell
.\install.ps1 -BackupAction RestorePlan -BackupTargetDrive E:
```

Produit :

```text
reports/backup/restore-plan-v7.txt
```

La commande génère un plan, elle ne lance pas de restauration destructive.

---

## 7. WSL uniquement

La distribution restaurée est importée sous un nom différent :

```text
Ubuntu-Restore-V7
```

L'Ubuntu actuel reste intact pendant la validation.

Le projet n'exécute jamais automatiquement :

```powershell
wsl --unregister Ubuntu
```

car cette commande détruit la distribution ciblée.

---

## 8. Windows complet

Pour une panne Windows/disque :

```text
WinRE / Recovery Drive
      ↓
WindowsImageBackup
      ↓
version explicitement choisie
      ↓
restauration bare-metal manuelle
```

La restauration complète reste une décision humaine, car elle peut remplacer partitions et données.

---

## 9. Quand refaire un Golden Backup ?

Après un changement **important et stabilisé**, par exemple :

- grosse mise à niveau Windows ;
- pilote majeur validé ;
- évolution WSL structurante ;
- changement important DevOps/OpenClaw ;
- avant une opération risquée.

Ne supprime pas immédiatement la dernière sauvegarde validée lorsque tu en crées une nouvelle.

---

## 10. Secrets

Les clés SSH, tokens, mots de passe et API keys doivent être conservés dans un stockage adapté.

Le dépôt Git ne doit jamais devenir un coffre de secrets.

Une sauvegarde contenant `D:\AI\OpenClaw\state` ou d'autres credentials doit être traitée comme un support sensible.
