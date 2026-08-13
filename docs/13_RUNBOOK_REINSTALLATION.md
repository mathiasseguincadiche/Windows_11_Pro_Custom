# Runbook — réinstallation et reconstruction complète de la workstation

Ce document est la **procédure opérationnelle** à suivre lorsqu'il faut reconstruire la machine après une réinstallation volontaire, une panne Windows, un remplacement de SSD ou une corruption importante.

Il n'est pas conçu pour enseigner tous les concepts : le tutoriel pédagogique d'installation est [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md). Ici, l'objectif est de savoir **quoi faire, dans quel ordre, quand s'arrêter et comment prouver que chaque phase est correcte**.

---

# 0. Avant toute chose : choisir le bon scénario

Ne réinstalle pas Windows automatiquement dès qu'un problème apparaît.

```text
Incident léger
├── mauvais réglage / tweak
│   └── Rollback du dépôt ou System Restore
│
├── Windows démarre mais fonctionne mal
│   └── diagnostic / réparation / éventuellement restauration V7
│
├── WSL seulement est endommagé
│   └── restaurer le VHDX sous un autre nom et valider
│
├── Windows ne démarre plus / disque remplacé
│   └── restauration WindowsImageBackup V7 via WinRE
│
└── aucune sauvegarde exploitable
    └── installation Windows propre + reconstruction depuis GitHub
```

## STOP immédiat si

- tu n'es pas certain du SSD que tu vas effacer ;
- des données importantes ne sont pas sauvegardées ;
- tu possèdes une sauvegarde V7 mais tu ne l'as pas encore vérifiée ;
- un disque semble physiquement défaillant ;
- tu n'as pas la clé de récupération d'un éventuel chiffrement externe au projet ;
- tu hésites entre `C:` et `D:` dans WinRE ou l'installateur Windows.

**Le dépôt n'automatise aucun formatage.** Une erreur manuelle de sélection de disque reste destructive.

---

# 1. Décider : restauration V7 ou reconstruction propre ?

## Choisir la restauration V7 si

Tu disposes d'un Golden Backup validé contenant :

```text
WindowsImageBackup\
Windows_11_Pro_Custom_Backup\V7\...
└── WSL\Ubuntu-GOLDEN-V7.vhdx
```

et que :

- le disque USB de sauvegarde est sain ;
- la version désirée apparaît dans `wbadmin get versions` ;
- le VHDX WSL passe son contrôle SHA-256 ;
- tu souhaites récupérer l'état complet de la machine tel qu'il était au moment du snapshot.

Voir directement : [Restauration V7](#17-restauration-v7--procédures-de-reprise).

## Choisir la reconstruction propre si

- aucune image V7 utilisable n'existe ;
- tu veux volontairement repartir d'un Windows neuf ;
- la sauvegarde est plus ancienne que l'état que tu veux reconstruire ;
- un changement majeur de stockage rend une reconstruction préférable ;
- tu veux profiter de la reproductibilité du dépôt plutôt que restaurer un état historique.

Dans ce cas, suis les phases 2 à 16.

---

# 2. Préparer les éléments nécessaires

Avant d'effacer quoi que ce soit, réunis :

```text
[ ] clé USB Windows 11 officielle
[ ] accès Internet
[ ] accès au compte/licence Windows
[ ] accès au dépôt GitHub
[ ] accès GitHub au dépôt privé OpenClaw si celui-ci doit être restauré
[ ] sauvegarde des fichiers personnels
[ ] disque Golden Backup V7 si disponible
[ ] éventuelles clés de récupération externes au projet
[ ] pilotes réseau de secours si nécessaire
```

Sources constructeur utiles :

- Windows 11 : <https://www.microsoft.com/software-download/windows11>
- MSI B850M Mortar WiFi : <https://www.msi.com/Motherboard/MAG-B850M-MORTAR-WIFI/support>
- AMD B850 chipset : <https://www.amd.com/en/support/downloads/drivers.html/chipsets/am5/b850.html>
- Intel Arc B580 : <https://www.intel.com/content/www/us/en/products/sku/241598/intel-arc-b580-graphics/downloads.html>

Ne conserve pas dans ce Runbook un numéro de BIOS ou de driver comme vérité permanente : vérifie la source officielle au moment de la reconstruction.

---

# 3. Vérifier le matériel et l'UEFI

Avant installation Windows :

```text
UEFI                       [requis]
CSM / Legacy               [désactivé]
TPM / AMD fTPM             [actif]
Secure Boot                [actif]
SVM / virtualisation       [actif]
Above 4G Decoding          [actif]
Resizable BAR              [actif]
RAM 6000                   [uniquement si stabilité connue]
```

## BIOS

Ne flashe pas automatiquement le BIOS.

Procédure :

1. relève la version actuelle ;
2. consulte le support MSI ;
3. lis les notes des versions stables ;
4. décide si le flash apporte une correction pertinente ;
5. évite une version bêta sans raison précise.

## Mémoire

Si la reconstruction fait suite à des crashes inexpliqués, repasse temporairement aux valeurs mémoire par défaut avant de diagnostiquer Windows. La cible 6000 MT/s ne vaut que si elle est réellement stable.

---

# 4. Protéger le deuxième T705 pendant l'installation

Architecture cible :

```text
T705 #1 -> C: NTFS -> Windows 11 Pro
T705 #2 -> D: NTFS -> DATA / WSL / OpenClaw
```

Les deux SSD peuvent être très difficiles à distinguer dans l'installateur Windows.

## Méthode recommandée

Si possible :

1. désactive dans l'UEFI ou déconnecte temporairement le T705 destiné à `D:` ;
2. laisse uniquement le SSD système visible pendant l'installation Windows ;
3. reconnecte/réactive le deuxième SSD après le premier boot réussi.

Cela protège `D:` d'une suppression accidentelle et évite que Windows place ses partitions EFI sur le mauvais disque.

---

# 5. Installer Windows 11 Pro proprement

Pour les explications écran par écran : [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md).

Checklist opératoire :

```text
[ ] démarrer la clé en mode UEFI
[ ] choisir Windows 11 Pro
[ ] choisir installation personnalisée
[ ] identifier le T705 système sans ambiguïté
[ ] supprimer les anciennes partitions UNIQUEMENT si réinstallation propre voulue
[ ] sélectionner l'espace non alloué du bon SSD
[ ] laisser Windows créer EFI/MSR/Recovery/Primary
[ ] laisser l'installation terminer
[ ] ne plus redémarrer sur la clé après la première phase
```

### Critère de sortie phase 5

La machine atteint le bureau Windows 11 Pro et démarre depuis Windows Boot Manager.

---

# 6. Terminer OOBE et établir un Windows sain

Avant les scripts du dépôt :

```text
[ ] édition Windows 11 Pro confirmée
[ ] activation vérifiée
[ ] compte utilisateur créé
[ ] réseau fonctionnel
[ ] date / heure / fuseau corrects
[ ] écran utilisable
[ ] bureau Windows accessible sans erreur
```

Le dépôt ne documente pas de contournement non supporté de l'OOBE.

---

# 7. Premier cycle Windows Update

Dans :

```text
Paramètres -> Windows Update
```

Répète :

```text
Rechercher
→ installer les mises à jour normales
→ redémarrer si demandé
→ rechercher à nouveau
```

jusqu'à obtenir un état stable.

**Ne sélectionne pas aveuglément tous les pilotes facultatifs.** Le projet préfère les pilotes chipset/GPU officiels des constructeurs.

### Critère de sortie phase 7

Windows Update ne présente plus de mise à jour normale importante en attente avant l'installation des drivers constructeur.

---

# 8. Installer les pilotes constructeur

Ordre conseillé :

## 8.1 AMD chipset B850

Source AMD officielle.

Après installation, redémarre si demandé.

## 8.2 Intel Arc B580

Source Intel officielle.

Vérifie après installation :

```text
Gestionnaire de périphériques -> Intel Arc B580 sans erreur
```

## 8.3 MSI / périphériques carte mère

Installe uniquement ce qui est nécessaire :

- LAN ;
- Wi-Fi ;
- Bluetooth ;
- audio ;
- autre périphérique réellement non reconnu.

Le projet ne dépend pas de MSI Center.

## 8.4 Contrôle Gestionnaire de périphériques

Objectif :

```text
Périphérique inconnu        : 0
Triangle jaune inattendu    : 0
Arc B580                    : OK
Réseau                      : OK
Wi-Fi/Bluetooth             : OK si utilisés
Audio                       : OK
```

### Critère de sortie phase 8

Le matériel nécessaire à l'exploitation courante est correctement reconnu.

---

# 9. Préparer `D:`

Reconnecte/réactive le deuxième T705 si nécessaire.

Dans Gestion des disques :

```text
T705 #2
→ GPT
→ volume simple
→ NTFS
→ lettre D:
```

Vérifie en PowerShell :

```powershell
Get-Volume -DriveLetter C,D | Format-Table DriveLetter,FileSystem,HealthStatus,Size,SizeRemaining
Get-Disk | Format-Table Number,FriendlyName,PartitionStyle,HealthStatus,Size
```

Attendu :

```text
C: NTFS Healthy
D: NTFS Healthy
```

**Ne crée aucune partition EXT4 physique.**

---

# 10. Vérifier les prérequis de sécurité et virtualisation

PowerShell administrateur :

```powershell
Confirm-SecureBootUEFI
Get-Tpm
systeminfo
```

Attendu :

```text
Secure Boot     -> True
TPM             -> présent / prêt
Virtualisation  -> activée firmware
```

Vérifie également l'écran :

```text
2560×1440
~240 Hz si le driver et l'écran le proposent
```

---

# 11. Récupérer le dépôt

Sur un Windows neuf, **Git for Windows peut être absent**.

## Méthode simple

Télécharge le ZIP du dépôt GitHub puis extrais-le dans :

```text
C:\Users\<user>\Documents\Windows_11_Pro_Custom
```

## Si Git est déjà installé

```powershell
git clone https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom.git
cd Windows_11_Pro_Custom
```

### Critère de sortie phase 11

Le dossier contient au minimum :

```text
README.md
menu.ps1
install.ps1
update.ps1
config\
docs\
manifest\ ou manifests\ selon arborescence réelle
scripts\
```

Dans ce dépôt, le dossier applicatif actuel est `manifests\`.

---

# 12. Audit initial : ne pas commencer par Apply

Ouvre PowerShell en administrateur dans le dépôt :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Mode Audit
```

L'Audit relit notamment :

- le préflight Windows ;
- l'état réel de la machine ;
- le système et le stockage ;
- le matériel ;
- les réglages Windows ;
- les applications ;
- WSL ;
- Defender ;
- workstation VS Code/WezTerm ;
- OpenClaw s'il existe déjà.

## STOP si l'Audit montre

- `D:` absent ;
- `C:` ou `D:` dans un filesystem inattendu ;
- incohérence matérielle majeure ;
- erreur préflight non comprise ;
- stockage dégradé ;
- autre condition fondamentale qui rendrait l'Apply dangereux.

### Critère de sortie phase 12

La machine possède une base cohérente permettant de construire le plan d'installation.

---

# 13. Prévisualiser le plan complet

Avant une reconstruction importante, il est recommandé d'exécuter :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Le plan V9 est calculé depuis `Verify` :

```text
DEJA_OK -> aucune mutation prévue
A_FAIRE -> Apply puis re-Verify
```

`PlanOnly` s'arrête avant les changements système après la phase de découverte.

Lis le plan. Si une action attendue est surprenante, ne valide pas tant que tu ne comprends pas pourquoi elle est proposée.

---

# 14. Lancer l'installation complète

## Via le menu V12

```powershell
.\menu.ps1
```

Puis :

```text
1. Installation complète
```

## Via PowerShell

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

`FullInstall` demande actuellement :

```text
Windows/apps/configuration
WSL2
stack DevOps
validation WSL
validation DevOps
qualification hardware
OpenClaw/OpenRouter
validation OpenClaw
```

L'orchestrateur :

1. relit l'état machine ;
2. construit le plan avant mutation ;
3. demande confirmation ;
4. tente un point de restauration avant changements ;
5. capture un benchmark avant ;
6. n'applique que les composants en écart ;
7. revalide chaque composant ;
8. capture les preuves après modification ;
9. écrit les logs et résumés.

---

# 15. Gérer les redémarrages et le premier lancement WSL

Une reconstruction Windows/WSL peut nécessiter un ou plusieurs redémarrages.

## Si Windows demande un reboot

1. termine proprement l'étape en cours ;
2. redémarre ;
3. retourne dans le dépôt ;
4. relance **la même commande**.

L'idempotence V9 doit faire apparaître les composants déjà convergés comme `DEJA_OK` plutôt que les réinstaller.

## Si Ubuntu demande la création d'un utilisateur

Lors du premier lancement WSL :

1. ouvre Ubuntu ;
2. crée l'utilisateur Linux demandé ;
3. reviens ensuite à l'orchestrateur.

Les racines de travail attendues sont :

```bash
mkdir -p ~/projects ~/labs ~/repositories
```

Ne place pas tes projets Linux dans `/mnt/c` ou `/mnt/d`.

---

# 16. Qualifications après reconstruction

## 16.1 Windows / workstation

```powershell
.\install.ps1 -Mode Verify
```

## 16.2 Hardware + WSL + DevOps

```powershell
.\install.ps1 -Mode Verify -ValidateHardware -ValidateWsl -ValidateDevOps
```

## 16.3 Avec OpenClaw

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateOpenClawAI
```

## Preuves matérielles manuelles

Si la qualification V5 indique `ACTION_REQUISE`, enregistre les preuves guidées :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Record -Interactive
```

À confirmer honnêtement :

```text
[ ] CSM désactivé
[ ] Above 4G actif
[ ] ReBAR actif
[ ] T705 dans les emplacements prévus
[ ] heatsinks / airflow SSD vérifiés
[ ] stabilité DDR5 6000 vérifiée
[ ] BIOS stable revu
[ ] drivers constructeur revus
```

Un élément non prouvé ne doit pas être marqué réussi simplement pour obtenir un verdict vert.

---

# 17. Restauration V7 — procédures de reprise

Cette section concerne un incident où un Golden Backup existe déjà.

Pour les détails : [`18_BACKUP_DISASTER_RECOVERY_V7.md`](18_BACKUP_DISASTER_RECOVERY_V7.md).

## 17.1 Générer d'abord le plan

Depuis un Windows encore utilisable :

```powershell
.\install.ps1 -BackupAction RestorePlan -BackupTargetDrive E:
```

Le fichier généré est :

```text
reports/backup/restore-plan-v7.txt
```

Le script vérifie l'intégrité du VHDX avant de produire le plan et **ne restaure rien automatiquement**.

## 17.2 WSL endommagé seulement

Principe :

```text
Ubuntu actuel        -> reste intact
Ubuntu-Restore-V7    -> importé à côté
                       ↓
                    validation
                       ↓
               décision humaine
```

Le plan propose typiquement :

```powershell
wsl --shutdown
wsl --import Ubuntu-Restore-V7 "D:\WSL\Ubuntu-Restore-V7" "E:\...\Ubuntu-GOLDEN-V7.vhdx" --vhd
wsl -l -v
wsl -d Ubuntu-Restore-V7
```

**Ne lance jamais `wsl --unregister Ubuntu` avant d'avoir validé la copie restaurée et sauvegardé ce qui doit l'être.**

## 17.3 Régression Windows légère

Utilise d'abord, selon le cas :

```text
install.ps1 -Mode Rollback
```

pour les réglages réellement gérés par le dépôt, ou **System Restore** pour revenir à un point de restauration Windows.

## 17.4 Windows ne démarre plus / remplacement du SSD

Démarre dans WinRE ou depuis une Recovery Drive.

Connecte le disque de sauvegarde.

**Attention : les lettres de lecteur peuvent changer dans WinRE. Vérifie-les.**

Lister les versions :

```text
wbadmin get versions -backupTarget:E:
```

La commande bare-metal de type :

```text
wbadmin start sysrecovery -version:<VERSION_IDENTIFIER> -backupTarget:E: -restoreAllVolumes
```

est lancée **manuellement**, après validation des disques et de la version choisie.

Le projet n'ajoute pas automatiquement `-recreateDisks` car cette option peut repartitionner les disques.

---

# 18. Rollback ≠ restauration

Ces termes ne signifient pas la même chose.

## Rollback du dépôt

```powershell
.\install.ps1 -Mode Rollback
```

Restaure les états initiaux enregistrés pour les réglages gérés : optimisations/tweaks/Defender/workstation selon les états disponibles.

Il **ne** :

- désinstalle pas toute la machine ;
- supprime pas WSL ;
- supprime pas OpenClaw ;
- restaure pas une image disque.

## RestorePlan V7

```powershell
.\install.ps1 -BackupAction RestorePlan -BackupTargetDrive E:
```

Produit une procédure de reprise sans l'exécuter.

## Bare-metal V7

Restauration manuelle depuis WinRE d'une image système complète.

---

# 19. Terminal V10 et VS Code après reconstruction

Une fois WSL installé, WezTerm doit ouvrir par défaut Ubuntu/Bash.

Architecture attendue :

```text
WezTerm
├── Ubuntu DevOps / Bash
└── PowerShell 7

VS Code
└── Ubuntu WSL / Bash
```

Dans Ubuntu, vérifie :

```bash
command -v starship
command -v fzf
command -v zoxide
command -v eza
command -v rg
```

Le profil géré se trouve sous :

```text
~/.config/windows11-pro-custom/devops.sh
```

Personnalisation locale :

```text
~/.config/windows11-pro-custom/local.sh
```

Guide : [`21_DEVOPS_TERMINAL_V10.md`](21_DEVOPS_TERMINAL_V10.md).

---

# 20. Smoke tests DevOps

Dans Ubuntu :

```bash
git --version
docker info
docker run --rm hello-world
kubectl version --client
helm version
terraform version
aws --version
ansible --version
gh --version
```

Pour Kubernetes local si nécessaire :

```bash
minikube start --driver=docker
kubectl get nodes
```

Ne considère pas seulement la présence du binaire : la validation du dépôt vérifie également les versions/contrats nécessaires.

---

# 21. OpenClaw / OpenRouter après reconstruction

Architecture :

```text
D:\AI\OpenClaw\
├── control-plane
├── npm-global
├── state
├── workspace
├── clawops
├── venv
├── logs
└── cache
```

Le control-plane suit un **SHA Git épinglé**, pas une branche mobile.

Si OpenClaw n'a pas été installé pendant `FullInstall` :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps -InstallOpenClawAI
```

Puis :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl -ValidateDevOps -ValidateOpenClawAI
```

Le dépôt privé nécessite une authentification GitHub au premier clone.

## Secrets

La clé OpenRouter n'est pas destinée à Git.

L'onboarding se fait explicitement quand nécessaire :

```powershell
openclaw onboard --auth-choice openrouter-api-key
```

Le rollback global ne supprime pas `D:\AI\OpenClaw`, car `state` peut contenir des credentials et des données de travail.

Guide : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

# 22. Créer le nouveau Golden Backup

**Ne crée pas le Golden Backup avant d'avoir qualifié la machine.**

Connecte un disque USB NTFS séparé, exemple `E:`.

Créer :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
```

Vérifier :

```powershell
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
```

Verdict attendu sur la vraie machine :

```text
VERDICT: V7 BACKUP READY
```

La politique actuelle exige notamment :

```text
C: + D: protégés
cible distincte physiquement
USB par défaut
NTFS
>= 100 Go libres avant lancement
WSL exporté en VHDX
SHA-256 vérifié
WinRE actif
```

Ne supprime pas immédiatement un Golden Backup précédent qui est encore connu comme bon.

---

# 23. Créer une Recovery Drive

Lance :

```powershell
recoverydrive.exe
```

Windows efface la clé choisie : cette opération reste volontairement interactive.

La Recovery Drive complète le Golden Backup ; elle ne remplace pas les données sauvegardées.

---

# 24. Maintenance après reconstruction

Le gestionnaire V11 est le mécanisme régulier :

```powershell
.\update.ps1 -Mode Audit
.\update.ps1 -Mode Apply
.\update.ps1 -Mode Verify
```

ou menu :

```text
3. Mises à jour complètes
```

Couverture :

```text
Windows Update
WinGet
WSL runtime
Ubuntu / APT
DevOps épinglé
VS Code extensions
```

Par défaut, V11 ne force ni drivers facultatifs, ni BIOS, ni firmware, ni reboot.

---

# 25. Journaux et preuves à conserver

Après une reconstruction, ouvre depuis le menu :

```text
9. Journaux et rapports
```

ou inspecte :

```text
logs/
logs/runs/<RunId>/events.ndjson
logs/runs/<RunId>/summary.json
reports/
```

À conserver comme preuve de bonne reconstruction :

- dernier résumé d'installation ;
- validations Windows/WSL/DevOps/hardware ;
- rapport backup V7 ;
- éventuels benchmarks avant/après ;
- rapport V11 après maintenance.

---

# 26. Dépannage : arbre de décision

## `install.ps1` échoue au préflight

```text
Ne pas relancer en boucle.
↓
Lire l'erreur précise.
↓
Vérifier C:/D:, droits admin, Windows, stockage.
```

## WinGet est absent

Ouvre Microsoft Store, mets **App Installer** à jour, puis relance la même commande.

## WSL demande un reboot

Redémarre Windows puis relance l'orchestrateur. Les étapes déjà conformes doivent devenir `DEJA_OK`.

## Ubuntu existe mais l'utilisateur n'est pas prêt

Ouvre la distribution, termine le premier lancement, crée l'utilisateur, puis relance.

## Docker refuse l'accès après installation

Ferme les shells WSL ou :

```powershell
wsl --shutdown
```

puis relance Ubuntu afin que l'appartenance au groupe soit rechargée.

## Une version DevOps est différente

Ne remplace pas manuellement par `latest` pour « faire disparaître » l'erreur.

Vérifie :

```text
config/devops/tool-versions.env
```

puis utilise l'orchestrateur/mise à jour pour converger vers la version du dépôt.

## Hardware V5 reste incomplet

Complète les preuves manuelles ; ne truque pas le résultat.

## OpenClaw ne clone pas le dépôt privé

Vérifie l'authentification GitHub / Git Credential Manager et l'accès au dépôt privé. Ne remplace pas le SHA épinglé par `main` pour contourner le problème.

## Une restauration WSL est incertaine

Importe sous `Ubuntu-Restore-V7`, valide-la à côté de l'ancienne distribution. Ne désenregistre pas l'original tant que la copie n'est pas prouvée.

---

# 27. Sign-off final

La reconstruction n'est terminée que lorsque cette checklist est satisfaite :

```text
WINDOWS
[ ] Windows 11 Pro activé
[ ] Windows Update stabilisé
[ ] aucun périphérique inconnu
[ ] AMD chipset valide
[ ] Arc B580 valide

STOCKAGE / SECURITY
[ ] C: NTFS / T705 système
[ ] D: NTFS / T705 DATA
[ ] GPT
[ ] Secure Boot
[ ] TPM 2.0
[ ] SVM
[ ] ReBAR + Above 4G vérifiés

WORKSTATION
[ ] applications automatiques présentes
[ ] PowerShell 7
[ ] VS Code
[ ] WezTerm
[ ] terminal Bash DevOps

WSL / DEVOPS
[ ] Ubuntu 26.04
[ ] HOME Linux ext4
[ ] projets dans ~/projects / ~/labs / ~/repositories
[ ] Docker
[ ] Kubernetes/Helm
[ ] Terraform
[ ] Ansible
[ ] AWS CLI
[ ] GitHub CLI

VALIDATION
[ ] .\install.ps1 -Mode Verify réussi
[ ] ValidateHardware réussi
[ ] ValidateWsl réussi
[ ] ValidateDevOps réussi
[ ] ValidateOpenClawAI réussi si OpenClaw utilisé

RECOVERY
[ ] Golden Backup V7 créé
[ ] Golden Backup V7 vérifié
[ ] Recovery Drive disponible/revue
[ ] restore-plan compréhensible

MAINTENANCE
[ ] V11 Audit/Apply/Verify exploitable
[ ] logs et reports accessibles
```

## Verdict d'exploitation

Lorsque les validations réellement demandées sont vertes et que la sauvegarde réelle est vérifiée, la workstation peut être considérée **prête à l'exploitation**.

La CI GitHub prouve les contrats du code ; elle ne remplace jamais cette validation physique sur la vraie machine.
