# Sauvegarde, restauration et reprise après incident

Une workstation reproductible doit pouvoir être reconstruite, mais une sauvegarde validée reste souvent le moyen le plus rapide de récupérer après panne.

Le projet combine Git, sauvegarde Windows, export WSL2 et procédures de reprise.

## Ce que GitHub protège

GitHub protège scripts, configurations, manifests, documentation et historique du code. Il ne protège pas automatiquement l'installation Windows réelle, `C:`, `D:`, le profil utilisateur, le VHDX WSL, les fichiers locaux non commités ou les credentials.

Les données de projets externes éventuellement présentes sur les volumes peuvent être incluses physiquement dans une image de disque, mais leur cohérence applicative et leur restauration fonctionnelle ne sont pas gérées par ce dépôt.

## Stratégie

```text
System Restore       -> rollback Windows léger
WindowsImageBackup   -> C: + D: + volumes critiques
Export WSL VHDX      -> Ubuntu restaurable séparément
GitHub               -> reconstruction du socle versionné
```

## Cible de sauvegarde

La sauvegarde de référence doit être stockée sur un **disque USB NTFS physiquement distinct** des deux Crucial T705 internes.

```text
C: protégé                     OUI
D: protégé                     OUI
cible externe par défaut       OUI
espace libre minimum           100 Go
WSL export                     VHDX
intégrité WSL                  SHA-256
restore destructif automatique NON
```

## Créer et vérifier

Exemple avec `E:` :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
```

Le parcours contrôle notamment la cible, le filesystem, la capacité, la séparation physique, WinRE, l'image Windows, l'export Ubuntu, le SHA-256 et le manifest.

## Générer un plan de restauration

```powershell
.\install.ps1 -BackupAction RestorePlan -BackupTargetDrive E:
```

Cette opération prépare les étapes sans lancer de restauration destructive.

## Restaurer WSL2

La restauration Linux est d'abord validée sous un nom distinct, par exemple `Ubuntu-Restore`, avant toute décision sur la distribution active.

Le dépôt ne doit jamais supprimer automatiquement la distribution active pour simplifier une restauration.

## Restaurer Windows

Une restauration bare-metal via WinRE et `WindowsImageBackup` peut remplacer des partitions et des données ; elle reste une décision humaine consciente.

## Rollback vs restauration

```powershell
.\install.ps1 -Mode Rollback
```

Le rollback restaure seulement des réglages gérés dont l'état initial est connu. Il ne remplace ni System Restore, ni la restauration WSL, ni une reprise bare-metal.

## Quand renouveler la sauvegarde ?

Après un changement important et stabilisé : mise à niveau Windows, pilote majeur, évolution WSL2, changement structurant de la stack DevOps ou avant une opération risquée.

Un projet externe installé sur la machine possède sa propre politique de sauvegarde fonctionnelle ; ce dépôt ne doit pas lui attribuer de procédure applicative.

## Secrets

Les clés SSH, tokens, mots de passe et API keys doivent rester dans un stockage adapté. Une image système contenant des profils utilisateurs et credentials locaux est un support sensible.

## Critère de réussite

```text
backup externe réel
+ image Windows vérifiable
+ export WSL vérifié
+ hash valide
+ WinRE disponible
+ procédure comprise
```

Une CI verte ne peut pas certifier à elle seule un vrai disque USB de sauvegarde : cette validation doit être réalisée sur la workstation réelle.
