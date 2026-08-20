# Runbook de reprise — restaurer ou reconstruire la workstation

Ce runbook s'utilise après un **incident majeur**, un remplacement de disque, une corruption importante de Windows/WSL2 ou une décision explicite de reconstruction.

Il ne doit pas être utilisé pour une simple dérive de configuration : dans ce cas, commencez par le [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).

> **Frontière de sécurité :** le dépôt peut auditer, converger, vérifier, préparer un rollback et produire des plans de reprise. Il ne formate jamais automatiquement les SSD et ne déclenche pas une restauration bare-metal destructive sans décision humaine.

## 1. Choisir réparation, restauration ou reconstruction

Commencez par cet arbre de décision :

```text
Windows démarre ?
│
├── Oui
│   ├── simple dérive de configuration
│   │   └── Audit → identité stockage Verify → PlanOnly → Apply → Verify
│   ├── réglage géré récemment en cause
│   │   └── Rollback si un état initial fiable existe
│   └── WSL2 seulement endommagé
│       └── restauration WSL isolée sous un nom distinct
│
└── Non
    ├── image / Golden Backup exploitable
    │   └── restauration contrôlée
    └── pas de sauvegarde exploitable
        └── reconstruction complète
```

### Questions à répondre avant toute action destructive

- Windows démarre-t-il ?
- `C:` et `E:` sont-ils accessibles ?
- l'identité physique des SSD est-elle certaine ?
- WSL2 démarre-t-il ?
- le VHDX Ubuntu existe-t-il ?
- une sauvegarde Windows vérifiée existe-t-elle ?
- un export ou VHDX WSL vérifié existe-t-il ?
- le support externe de sauvegarde est-il disponible ?
- le problème semble-t-il logiciel ou matériel ?

**STOP :** ne reformatez rien si l'identité du disque ou la valeur des données restantes n'est pas certaine.

## 2. Si Windows démarre encore

### Observer

```powershell
.\install.ps1 -Mode Audit
```

### Vérifier l'identité du stockage

```powershell
.\scripts\bootstrap\00_storage_identity.ps1 -Mode Verify
```

Si la baseline est absente ou la topologie a changé volontairement, suivez [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md). Ne remplacez pas une baseline pour masquer une alerte.

### Prévisualiser une réparation par convergence

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Si le plan est compris et cohérent :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

Une réinstallation Windows est inutile si la convergence corrige proprement l'écart.

## 3. Si un réglage géré doit être annulé

Lorsque le dépôt possède réellement un état initial rollbackable :

```powershell
.\install.ps1 -Mode Rollback
```

Le rollback ne restaure pas l'intégralité de Windows ni les données d'un projet externe. Il ne faut pas le présenter comme une restauration bare-metal.

## 4. Protéger ce qui est encore récupérable

Avant toute opération destructrice, sauvegardez ce qui reste accessible :

```text
données personnelles
projets non poussés sur Git
clés SSH
configuration locale
secrets depuis leur stockage sécurisé
VHDX / export WSL
documents non synchronisés
données applicatives importantes
```

Ne stockez jamais des secrets dans le dépôt Git « temporairement ».

Si une sauvegarde de référence saine existe déjà, ne l'écrasez pas avant d'avoir terminé la reprise.

## 5. Écarter une panne matérielle

Avant de réinstaller un système instable, vérifiez au minimum :

- SSD visibles dans l'UEFI ;
- RAM détectée ;
- refroidissement plausible ;
- alimentation stable ;
- absence d'erreur matérielle connue ;
- BIOS dans un état stable ;
- périphériques essentiels reconnus.

En cas de crashs aléatoires, revenez à des réglages stables avant de conclure à une corruption logicielle.

Référence : [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

## 6. Préparer une réinstallation Windows si elle est réellement nécessaire

Utilisez une image Windows 11 officielle et un média UEFI fiable.

La workstation cible n'a pas besoin d'un contournement TPM/Secure Boot. Les réglages attendus sont documentés dans [`02_BIOS_DRIVERS.md`](02_BIOS_DRIVERS.md).

### Sécuriser les deux SSD

La machine utilise deux Crucial T705 similaires :

```text
SSD système -> C: -> Windows 11 Pro
SSD DATA    -> E: -> données / WSL2
```

Si possible et sans risque matériel, déconnectez ou désactivez temporairement le SSD DATA pendant l'installation Windows. Sinon, vérifiez soigneusement numéro, capacité et rôle avant toute suppression de partition.

**STOP :** une suppression sur le mauvais SSD est irréversible sans sauvegarde.

## 7. Réinstaller Windows 11 Pro

Pendant l'installation personnalisée :

1. confirmez une dernière fois que les données importantes sont sauvegardées ;
2. sélectionnez uniquement le SSD système ;
3. supprimez uniquement les partitions Windows que vous avez décidé de recréer ;
4. laissez Windows recréer GPT/EFI/MSR/Recovery/Primary ;
5. installez Windows 11 Pro ;
6. redémarrez sur Windows Boot Manager.

Le dépôt ne réalise pas cette phase automatiquement.

## 8. Stabiliser Windows avant la convergence

Avant d'exécuter les optimisations ou la stack DevOps :

1. vérifiez l'édition et l'activation ;
2. vérifiez réseau, heure et fuseau ;
3. exécutez Windows Update ;
4. redémarrez si nécessaire ;
5. installez les pilotes chipset AMD ;
6. installez le pilote Intel Arc ;
7. complétez uniquement les pilotes MSI réellement nécessaires ;
8. vérifiez le Gestionnaire de périphériques.

Ne poursuivez pas tant que des périphériques essentiels restent inconnus ou instables.

## 9. Restaurer ou recréer `E:`

Si le second SSD est intact, ne le reformatez pas inutilement.

S'il doit réellement être recréé :

```text
GPT
└── E: NTFS
```

Architecture gérée :

```text
E:\
├── DATA\
├── WSL\
│   ├── Ubuntu-DevOps\
│   └── swap\
├── ISO\
└── exports\
```

Le filesystem ext4 d'Ubuntu reste dans le VHDX WSL2.

Référence : [`03_STOCKAGE.md`](03_STOCKAGE.md).

## 10. Récupérer le dépôt

Exemple :

```powershell
mkdir C:\Dev -ErrorAction SilentlyContinue
cd C:\Dev
git clone https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom.git
cd Windows_11_Pro_Custom
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Mode Audit
```

Conservez cet audit comme premier état factuel de la reconstruction.

## 11. Réenrôler ou vérifier l'identité physique

Après remplacement ou reconstruction du stockage :

```powershell
.\scripts\bootstrap\00_storage_identity.ps1 -Mode Audit
```

Si une baseline restaurée correspond toujours à la topologie réelle :

```powershell
.\scripts\bootstrap\00_storage_identity.ps1 -Mode Verify
```

Si la baseline est légitimement absente, contrôlez humainement la topologie puis effectuez l'enrôlement selon [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md).

## 12. Prévisualiser puis reconstruire la configuration

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Relisez le plan.

Si le plan est cohérent :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

Un redémarrage demandé par Windows ou WSL2 n'est pas un échec. Effectuez-le puis relancez la même intention.

## 13. Restaurer WSL2 de manière sûre

Si un VHDX ou export valide existe, préférez une restauration parallèle sous un nom distinct, par exemple :

```text
Ubuntu-Restore
```

Principe :

```text
Ubuntu actuelle
+
Ubuntu-Restore
   ↓
validation indépendante
   ↓
choix humain
```

Vérifiez la copie restaurée avant toute suppression :

- utilisateur et HOME ;
- projets ;
- permissions ;
- Docker ;
- outils DevOps ;
- fichiers personnels ;
- intégrité attendue.

Ne lancez jamais automatiquement :

```powershell
wsl --unregister Ubuntu
```

Cette commande détruit la distribution ciblée.

Le drill isolé est documenté dans [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md).

## 14. Revalider WSL2 et la stack DevOps

```powershell
wsl --shutdown
.\install.ps1 -Mode Verify -ValidateWsl -ValidateDevOps
```

Si une réparation DevOps est nécessaire :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

`/mnt/c` et `/mnt/e` restent accessibles pour des échanges ponctuels avec Windows, mais sont **interdits comme racines de projets ou de workspaces DevOps**. Après reprise, les projets Linux actifs doivent donc revenir dans le filesystem ext4 WSL2.

## 15. Revalider Windows Terminal et VS Code

Vérifiez que Windows Terminal expose :

```text
PowerShell 7 - DevOps
Ubuntu - DevOps
```

Validation ciblée :

```powershell
.\scripts\windows\31_windows_terminal.ps1 -Mode Verify
```

VS Code doit ouvrir les projets WSL sous `/home/<user>/...`.

## 16. Restaurer les données personnelles

Restaurez les données après stabilisation du système de base lorsque c'est possible :

```text
workstation stable
→ profil et documents
→ projets absents de Git
→ clés et secrets depuis leur stockage sécurisé
→ données applicatives
→ projets externes avec leurs propres procédures
```

Évitez de recopier en bloc d'anciens caches ou dossiers système qui pourraient réintroduire la cause de l'incident.

## 17. Projets externes

OpenClaw/OpenRouter n'est pas reconstruit par ce dépôt.

Pour ce projet, utilisez exclusivement `mathiasseguincadiche/openclaw_openrouter` et sa procédure propre. `Windows_11_Pro_Custom` ne possède ni son runtime, ni ses modèles, ni ses agents, ni ses validations.

Référence : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

## 18. Validation finale après reprise

Exécutez :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

Puis :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Le second plan doit tendre vers `DÉJÀ OK`.

Revalidez ensuite la preuve `PHYSICAL`, la sauvegarde et la restaurabilité selon [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md).

## 19. Critères de sortie de crise

La reprise est terminée lorsque :

- l'identité physique `C:` / `E:` est certaine ;
- Windows est stable et qualifié ;
- le matériel est qualifié ;
- WSL2 et la stack DevOps sont conformes ;
- Windows Terminal et VS Code sont cohérents ;
- les données restaurées ont été vérifiées ;
- aucun projet externe n'a été confondu avec le périmètre workstation ;
- l'idempotence est démontrée ;
- la sauvegarde de référence est valide ;
- la dérive `PHYSICAL` est absente ou expliquée.

Checklist générale : [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md).

## À retenir

Le but de ce runbook n'est pas de réinstaller le plus vite possible. Il est de **choisir la réponse la moins destructive compatible avec l'incident**, protéger les données encore récupérables, reconstruire uniquement ce qui doit l'être et prouver ensuite que la workstation est de nouveau conforme.
