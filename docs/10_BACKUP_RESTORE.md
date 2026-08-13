# Sauvegarde, restauration et reprise après incident

Une workstation reproductible doit pouvoir être **reconstruite**, mais une reconstruction n'est pas toujours le moyen le plus rapide de récupérer une machine réelle après panne.

Le projet combine donc Git, sauvegarde Windows, export WSL2 et procédures de reprise.

---

## Ce que GitHub protège

GitHub protège :

- scripts ;
- configurations ;
- manifests ;
- documentation ;
- historique du code.

Il ne protège pas automatiquement :

- l'installation Windows réelle ;
- `C:` ;
- les données de `D:` ;
- le profil utilisateur ;
- le VHDX WSL réel ;
- les données OpenClaw ;
- les fichiers locaux non commités ;
- les credentials.

GitHub est donc une **source de reconstruction**, pas une image de sauvegarde de la machine.

---

## Stratégie de protection

```text
System Restore
      ↓
rollback Windows léger

WindowsImageBackup
      ↓
C: + D: + volumes critiques

Export WSL VHDX + SHA-256
      ↓
Ubuntu restaurable séparément

GitHub
      ↓
reconstruction du socle versionné
```

Ces couches répondent à des incidents différents.

---

## Cible de sauvegarde

La sauvegarde de référence doit être stockée sur un **disque USB NTFS physiquement distinct** des deux Crucial T705 internes.

Politique courante :

```text
C: protégé                         OUI
D: protégé                         OUI
cible externe par défaut           OUI
espace libre minimum               100 Go
WSL export                         VHDX
intégrité WSL                      SHA-256
restore destructif automatique     NON
```

Un dossier `D:\BACKUPS` sur le SSD interne n'est pas une protection suffisante de ce même disque.

---

## Créer une sauvegarde de référence

Exemple avec un disque USB monté sur `E:` :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
```

Le parcours vérifie notamment :

1. présence de la cible ;
2. filesystem NTFS ;
3. espace libre ;
4. séparation physique avec `C:` et `D:` ;
5. disponibilité de WinRE ;
6. création d'un point de restauration lorsque possible ;
7. arrêt propre de WSL ;
8. création de l'image Windows ;
9. export de la distribution Ubuntu en VHDX ;
10. calcul du SHA-256 ;
11. écriture d'un manifest de sauvegarde.

Le script ne doit pas annoncer une sauvegarde fiable uniquement parce que `wbadmin` ou `wsl --export` a démarré : les artefacts doivent être vérifiables.

---

## Vérifier une sauvegarde

```powershell
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
```

La vérification contrôle notamment :

- présence d'une image Windows récupérable ;
- état WinRE ;
- manifest ;
- export WSL ;
- hash SHA-256 ;
- cohérence de la politique de sécurité ;
- absence de procédure destructive exécutée automatiquement.

Une sauvegarde non vérifiée ne doit pas être considérée comme un plan de reprise fiable.

---

## Générer un plan de restauration

```powershell
.\install.ps1 -BackupAction RestorePlan -BackupTargetDrive E:
```

Cette opération prépare les étapes de reprise **sans lancer la restauration destructive**.

Le principe est :

```text
analyser le backup
   ↓
identifier les options de reprise
   ↓
générer un plan
   ↓
laisser l'utilisateur choisir
```

---

## Restaurer WSL2 sans détruire l'Ubuntu actuel

La restauration Linux est conçue pour être validée **à côté** de la distribution active.

Au lieu de supprimer immédiatement Ubuntu, le projet importe d'abord la sauvegarde sous un nom distinct, par exemple :

```text
Ubuntu-Restore
```

Cela permet de vérifier :

- démarrage ;
- utilisateur ;
- fichiers ;
- Docker ;
- outils DevOps ;
- projets ;
- intégrité globale.

Le projet n'exécute jamais automatiquement :

```powershell
wsl --unregister Ubuntu
```

sur la distribution active pour « simplifier » une restauration.

---

## Restaurer Windows complètement

Pour une panne Windows ou un remplacement de disque :

```text
WinRE / média de récupération
      ↓
WindowsImageBackup
      ↓
version explicitement choisie
      ↓
restauration bare-metal manuelle
```

Une restauration bare-metal peut remplacer des partitions et des données. Elle doit donc rester une décision humaine consciente.

Le dépôt peut préparer les informations utiles ; il ne clique pas automatiquement sur le point de non-retour.

---

## Différence entre rollback et restauration

### Rollback

Utilisé pour revenir sur un réglage géré par le dépôt lorsque l'état initial est connu.

```powershell
.\install.ps1 -Mode Rollback
```

### System Restore

Retour Windows léger à un point de restauration.

### Restauration WSL

Réimport d'un VHDX sauvegardé et validation indépendante.

### Bare-metal recovery

Restauration complète de l'image Windows sur le stockage physique.

Ces mécanismes ne sont pas interchangeables.

---

## Quand créer une nouvelle sauvegarde de référence ?

Après un changement important **et stabilisé**, par exemple :

- grosse mise à niveau Windows ;
- changement de pilote majeur validé ;
- évolution structurante de WSL2 ;
- changement important de la stack DevOps ;
- intégration OpenClaw stabilisée ;
- avant une opération risquée.

Ne supprime pas immédiatement la dernière sauvegarde validée lorsque tu en crées une nouvelle.

---

## Après une réinstallation

Le Runbook complet de reconstruction est :

[`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md).

Il sert lorsque :

- aucune image fiable n'est disponible ;
- on veut repartir d'un Windows propre ;
- la restauration complète n'est pas souhaitable ;
- on doit reconstruire le socle depuis Git.

---

## Secrets et données sensibles

Les clés SSH, tokens, mots de passe et API keys doivent être conservés dans un stockage adapté.

Une sauvegarde contenant :

```text
D:\AI\OpenClaw\state
profil utilisateur
clés SSH
credentials locaux
```

est un support sensible et doit être protégée physiquement.

Le dépôt Git ne doit jamais devenir un coffre de secrets.

---

## Critère de réussite

La stratégie de reprise est considérée prête lorsque :

```text
backup externe réel
+
image Windows vérifiable
+
export WSL vérifié
+
hash valide
+
WinRE disponible
+
procédure comprise
```

Une CI verte ne peut pas créer ni certifier à elle seule un vrai disque USB de sauvegarde : cette validation doit être réalisée sur la workstation réelle.
