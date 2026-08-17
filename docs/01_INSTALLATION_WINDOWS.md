# Installation Windows 11 Pro — guide complet débutant

Ce guide explique comment partir d'un PC vide ou fraîchement réinstallé et obtenir une base **Windows 11 Pro propre et saine**, prête à accueillir la workstation décrite par ce dépôt.

Il est volontairement détaillé. Les opérations manuelles ou potentiellement dangereuses sont signalées explicitement.

> **Règle de sécurité :** aucun script de ce dépôt ne formate automatiquement un SSD, ne flashe le BIOS et ne déclenche une restauration bare-metal. Le partitionnement initial et l'installation de Windows restent des opérations humaines contrôlées.

Pour comprendre le projet avant de commencer, lire [`../README.md`](../README.md) puis [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md).

---

## Résultat attendu

À la fin de l'installation de base :

```text
Crucial T705 #1
└── C: NTFS
    └── Windows 11 Pro

Crucial T705 #2
└── D: NTFS
    ├── données
    ├── D:\WSL\Ubuntu-DevOps
    └── D:\WSL\swap

UEFI
├── démarrage UEFI
├── CSM désactivé
├── Secure Boot actif
├── TPM / AMD fTPM actif
├── SVM actif
├── Above 4G Decoding actif
└── Resizable BAR actif
```

Le filesystem Linux de WSL2 sera contenu dans un **VHDX** sur `D:`. Ne crée pas de partition EXT4 physique pour Ubuntu.

---

## Matériel concerné

La workstation cible :

- AMD Ryzen 7 7700 ;
- MSI MAG B850M Mortar WiFi ;
- 48 Go DDR5 ;
- Intel Arc B580 12 Go ;
- deux Crucial T705 PCIe 5.0 ;
- écran 2560×1440 à haut taux de rafraîchissement.

La configuration machine-readable se trouve sous `config/hardware/`.

Le dépôt pourra ensuite vérifier automatiquement une partie de ces éléments. D'autres points — ReBAR, emplacement physique des SSD, refroidissement, stabilité RAM — nécessitent une preuve humaine.

Guide : [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

---

## Avant de commencer

### Obligatoire

Prépare :

- une clé USB de 8 Go ou plus ;
- une connexion Internet disponible après l'installation ;
- une licence ou un droit numérique Windows 11 Pro ;
- l'accès à ce dépôt depuis un autre appareil si nécessaire ;
- une sauvegarde de tes données personnelles si la machine a déjà été utilisée.

### Recommandé

Conserve sur un support séparé :

- pilote réseau/Wi-Fi MSI si Windows ne reconnaît pas le réseau ;
- pilote chipset AMD B850 ;
- pilote Intel Arc ;
- clés de récupération ou informations de chiffrement importantes ;
- informations de compte nécessaires à tes logiciels.

### À éviter

Ne commence pas par :

- une ISO Windows provenant d'un site non officiel ;
- un « driver pack » générique ;
- un script de debloat agressif ;
- un overclocking CPU/GPU ;
- une fréquence mémoire incertaine ;
- une restauration de réglages anciens non compris.

Le but est d'obtenir d'abord une base **stable et vérifiable**.

---

## Télécharger Windows 11

Utilise l'image Windows 11 x64 stable officielle de Microsoft.

Si tu télécharges une ISO manuellement, tu peux vérifier son SHA-256 avec :

```powershell
Get-FileHash .\Windows11.iso -Algorithm SHA256
```

Compare uniquement avec la valeur fournie pour **la même image, édition et langue**.

Le projet ne dépend pas d'une Insider Preview ni d'un Windows modifié par un tiers.

---

## Créer la clé USB

### Depuis Windows

La méthode la plus simple est l'outil officiel de création de média Microsoft.

Une ISO officielle peut également être écrite avec un outil tel que Rufus, sans désactiver les exigences de sécurité supportées par cette machine.

### Depuis Linux avec Ventoy

Si la clé Ventoy est déjà préparée :

1. monte la grande partition `Ventoy` ;
2. copie l'ISO Windows 11 officielle ;
3. démonte proprement la clé ;
4. démarre le PC en mode UEFI sur la clé ;
5. sélectionne l'ISO dans le menu Ventoy.

La configuration matérielle du projet respecte TPM 2.0, Secure Boot et les exigences normales de Windows 11 : aucun contournement n'est nécessaire.

---

## Préparer l'UEFI / BIOS

Si la machine vient d'être assemblée ou si le firmware contient de nombreux essais anciens, charge d'abord une base saine puis applique seulement les réglages nécessaires.

### Réglages attendus

| Réglage | Cible | Raison |
| --- | --- | --- |
| Boot mode | UEFI | GPT / Secure Boot |
| CSM / Legacy | désactivé | éviter le boot hérité |
| TPM / AMD fTPM | actif | sécurité Windows |
| Secure Boot | actif | chaîne de démarrage |
| SVM | actif | virtualisation / WSL2 |
| Above 4G Decoding | actif | plateforme GPU moderne |
| Resizable BAR | actif | fonctionnement optimal Intel Arc |

Le dépôt ne modifie jamais ces réglages automatiquement.

### RAM DDR5

La cible peut être 6000 MT/s, mais uniquement si la stabilité est démontrée.

Pendant une réinstallation de dépannage :

```text
stabilité connue à 6000
        ↓
profil validé acceptable

instabilité / nouveau BIOS / doute
        ↓
revenir temporairement aux paramètres mémoire sûrs
        ↓
installer et valider Windows
        ↓
retester la mémoire séparément
```

Une workstation DevOps doit privilégier la fiabilité aux quelques pourcents de performance théorique.

### Mise à jour BIOS

Le dépôt ne flashe pas le BIOS.

Avant une mise à jour :

1. relever la version actuelle ;
2. consulter la page support MSI de la carte mère ;
3. lire les notes de version ;
4. préférer une version stable ;
5. ne flasher que pour une raison claire : stabilité, sécurité, compatibilité ou bug connu.

Ne mets pas à jour le firmware au milieu d'un diagnostic simplement pour « avoir la dernière version ».

---

## Identifier correctement les deux SSD

Les deux SSD sont des Crucial T705 similaires. L'erreur la plus grave serait de supprimer les partitions du mauvais disque.

### Méthode la plus sûre

Si c'est simple matériellement, désactive temporairement dans l'UEFI ou déconnecte le SSD destiné à `D:` pendant l'installation de Windows.

Cela garantit :

- que l'installateur ne peut pas effacer le disque de données ;
- que les partitions EFI/Recovery sont créées sur le SSD système ;
- que le disque à sélectionner est évident.

### Si les deux SSD restent présents

À chaque étape de partitionnement :

- vérifie le numéro et la capacité ;
- ne supprime aucune partition si tu n'es pas certain du disque ;
- en cas de doute, quitte l'installateur et vérifie l'UEFI ou le montage physique.

---

## Installer Windows 11 Pro

### Démarrage

1. branche la clé USB ;
2. ouvre le Boot Menu MSI ;
3. choisis l'entrée **UEFI** de la clé ;
4. démarre l'installation.

### Édition

Quand l'édition est demandée, choisis **Windows 11 Pro** si ta licence correspond à Pro.

### Installation personnalisée

Pour une installation propre, utilise l'option personnalisée.

Sur le T705 système uniquement :

1. confirme que les données utiles sont sauvegardées ;
2. supprime les anciennes partitions Windows si tu veux réellement repartir de zéro ;
3. sélectionne l'espace non alloué ;
4. laisse Windows créer automatiquement les partitions GPT/EFI/MSR/Recovery/Primary.

> Supprimer une partition détruit ses données. Vérifie le disque avant chaque suppression.

### Premier redémarrage

Après la copie des fichiers, laisse Windows démarrer sur son propre SSD. Retire la clé ou choisis Windows Boot Manager si l'installateur revient sur l'USB.

---

## OOBE et premier bureau

Suis l'assistant Windows officiel jusqu'au bureau.

Pendant cette phase :

- vérifie langue et clavier ;
- choisis un nom de machine clair ;
- configure ton compte et ton authentification ;
- lis les options de confidentialité ;
- n'applique encore aucun tweak du dépôt.

Une fois sur le bureau, vérifie :

```text
Paramètres → Système → Activation
```

Puis :

- édition Windows 11 Pro ;
- activation ;
- heure et fuseau ;
- réseau ;
- résolution écran.

Commande utile :

```powershell
winver
```

---

## Premier cycle Windows Update

Avant d'appliquer les optimisations du dépôt, termine un premier cycle normal de Windows Update.

```text
Paramètres → Windows Update → Rechercher des mises à jour
```

Installe les mises à jour standards, redémarre si nécessaire, puis vérifie à nouveau jusqu'à obtenir un état stable.

Pour les drivers facultatifs, évite d'installer tout mécaniquement : le projet privilégie les sources constructeur pertinentes pour le chipset AMD et le GPU Intel.

La maintenance régulière sera ensuite gérée par [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

## Installer les pilotes principaux

### Chipset AMD B850

Installe le package chipset AMD officiel adapté à Windows 11 et au chipset B850.

Après installation, redémarre si demandé.

### Intel Arc B580

Installe le pilote Intel Arc officiel, puis vérifie :

- GPU présent sans erreur dans le Gestionnaire de périphériques ;
- résolution correcte ;
- fréquence d'affichage cible disponible ;
- ReBAR / Above 4G validés dans l'UEFI.

### MSI : LAN, Wi-Fi, Bluetooth, audio

Utilise les pilotes MSI uniquement lorsque Windows n'a pas déjà un pilote correct ou lorsqu'un composant spécifique de la carte mère l'exige.

Le dépôt ne dépend pas de MSI Center pour fonctionner.

### Gestionnaire de périphériques

Avant de poursuivre :

```text
Win + X → Gestionnaire de périphériques
```

Objectif :

- aucun périphérique inconnu ;
- aucun triangle jaune inattendu ;
- Arc B580 détectée ;
- réseau/Wi-Fi/Bluetooth fonctionnels ;
- audio fonctionnel ;
- stockage visible.

---

## Préparer le second T705 comme `D:`

Si le second SSD avait été déconnecté, éteins la machine puis reconnecte-le.

Dans :

```text
Win + X → Gestion des disques
```

Pour un disque neuf :

1. initialise-le en GPT ;
2. crée un volume simple ;
3. formate-le en NTFS ;
4. attribue la lettre `D:` ;
5. donne-lui un libellé clair si souhaité.

Ne crée pas de partition EXT4 physique.

Architecture attendue :

```text
D:\
├── DATA\
├── WSL\
│   ├── Ubuntu-DevOps\
│   └── swap\
├── ISO\
└── exports\
```

Les dossiers seront créés ou utilisés progressivement selon les composants activés par la workstation. Les projets externes utilisent leurs propres conventions et ne font pas partie de ce contrat.

Guide : [`03_STOCKAGE.md`](03_STOCKAGE.md).

---

## Vérifications Windows avant automatisation

Ouvre PowerShell et vérifie :

```powershell
Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsArchitecture
Get-Volume | Select-Object DriveLetter, FileSystem, FileSystemLabel, SizeRemaining, Size
Confirm-SecureBootUEFI
Get-Tpm
```

Vérifie aussi que la virtualisation est disponible.

Le dépôt fera des contrôles plus complets ensuite ; cette étape sert surtout à ne pas démarrer l'automatisation sur une base manifestement incorrecte.

---

## Récupérer le dépôt

Installe Git si nécessaire, puis clone le dépôt dans un emplacement Windows simple et accessible.

Exemple :

```powershell
mkdir C:\Dev -ErrorAction SilentlyContinue
cd C:\Dev
git clone https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom.git
cd Windows_11_Pro_Custom
```

Ne mets pas le dépôt dans un dossier temporaire ou un emplacement synchronisé dont le comportement n'est pas maîtrisé.

---

## Première inspection et enrôlement V25

Commencer par l'audit non mutatif :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Mode Audit
```

L'audit doit observer l'état réel et signaler les éléments manquants ou incohérents.

Avant le premier `PlanOnly` ou la première installation complète, ouvrir
PowerShell en administrateur et qualifier l'identité physique des deux volumes :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Audit
```

Contrôler humainement que `C:` est le volume Windows attendu, que `D:` est le
second Crucial T705 NTFS destiné aux données/WSL, et qu'ils résident sur deux SSD
physiques distincts. Enregistrer ensuite la baseline une seule fois :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 `
  -Mode Record `
  -ConfirmHealthyTopology
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Verify
```

Si une baseline existe déjà, ne pas la remplacer : exécuter seulement
`-Mode Verify`. Une divergence inexpliquée doit interrompre l'installation et
être investiguée selon [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md).

Après le verdict `STORAGE IDENTITY READY`, prévisualiser :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Guide d'orchestration : [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md).

---

## Méthode recommandée : centre de contrôle

L'interface la plus simple est :

```text
START_MENU.cmd
```

ou :

```powershell
.\menu.ps1
```

Pour une première configuration, choisir **Installation complète**.

Le menu ne remplace pas `install.ps1` : il appelle les orchestrateurs existants avec les bonnes intentions et l'élévation UAC lorsque nécessaire.

Guide : [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md).

---

## Installation complète en ligne de commande

Si tu préfères voir explicitement la commande :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

L'orchestrateur applique uniquement les écarts détectés et revalide les composants après modification.

Le raccourci `-FullInstall` active la stack DevOps ainsi que les validations WSL, DevOps et matérielles prévues par la workstation. Il ne déclenche aucun projet externe.

La liste exacte des composants peut évoluer, mais l'objectif reste :

```text
Windows de base
   ↓
applications et outils Windows
   ↓
réglages gérés
   ↓
WSL2 / Ubuntu
   ↓
stack DevOps
   ↓
terminal / VS Code
   ↓
validation
```

---

## Premier lancement Ubuntu

Lors de la première création ou installation de la distribution, Ubuntu peut demander la création de l'utilisateur Linux.

Choisis :

- un nom d'utilisateur Linux normal ;
- un mot de passe distinct si tu le souhaites ;
- **pas** un workflow quotidien en root.

Le mot de passe `sudo` doit être saisi directement dans Linux lorsqu'il est demandé ; il ne doit pas être stocké dans Git ni passé comme argument journalisé.

---

## Vérifier WSL2

Après installation :

```powershell
wsl --shutdown
wsl -d Ubuntu
```

Dans Ubuntu :

```bash
whoami
uname -a
nproc
free -h
swapon --show
ps -p 1 -o comm=
findmnt -T "$HOME"
```

Le HOME doit être sur le filesystem Linux ext4.

Les projets DevOps doivent vivre sous `/home/<user>/...`.

Guide : [`06_WSL2.md`](06_WSL2.md).

---

## Vérifier la stack DevOps

Depuis PowerShell :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl -ValidateDevOps
```

Dans Ubuntu, quelques contrôles utiles :

```bash
docker info
terraform version
ansible-playbook --version
kubectl version --client
helm version
aws --version
gh --version
```

Guide : [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md).

---

## Qualification matérielle

Une fois les pilotes et Windows stabilisés :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

Puis renseigne les preuves manuelles si nécessaire :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Record -Interactive
```

Guide : [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

---

## Validation complète

Quand la workstation semble prête :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

Puis :

```powershell
.\update.ps1 -Mode Verify
```

La validation d'OpenClaw/OpenRouter n'appartient pas à cette commande ni à ce dépôt. Si la plateforme IA est utilisée sur la machine, suivre exclusivement `mathiasseguincadiche/openclaw_openrouter`.

Guide : [`11_VALIDATION.md`](11_VALIDATION.md).

---

## Frontière avec OpenClaw / OpenRouter

`Windows_11_Pro_Custom` ne prépare pas, n'installe pas, ne configure pas et ne qualifie pas OpenClaw/OpenRouter.

Le dépôt `mathiasseguincadiche/openclaw_openrouter` possède ses propres chemins, contrats, procédures et validateurs. Les deux projets peuvent être utilisés sur la même machine sans qu'un dépôt orchestre l'autre.

Guide de frontière : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

## Créer la sauvegarde de référence

Ne considère pas la workstation terminée tant qu'elle n'est pas récupérable.

Avec un disque USB NTFS séparé, par exemple `E:` :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
```

Puis :

```powershell
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
```

La cible externe doit être physiquement distincte des deux T705 internes.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

## Maintenance après installation

Pour auditer les mises à jour :

```powershell
.\update.ps1 -Mode Audit
```

Pour appliquer les mises à jour autorisées :

```powershell
.\update.ps1 -Mode Apply
```

Le gestionnaire traite les couches qu'il connaît sans :

- flasher le BIOS ;
- installer arbitrairement tous les drivers facultatifs ;
- forcer un redémarrage ;
- faire un changement majeur Ubuntu ;
- remplacer les outils DevOps épinglés par `latest` ;
- mettre à jour un projet externe OpenClaw/OpenRouter.

Guide : [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

## Checklist finale

```text
[ ] Windows 11 Pro installé et activé
[ ] UEFI / Secure Boot / TPM / SVM vérifiés
[ ] Above 4G / ReBAR vérifiés
[ ] chipset AMD installé
[ ] pilote Intel Arc installé
[ ] aucun périphérique inconnu
[ ] C: NTFS correct
[ ] D: NTFS correct
[ ] dépôt récupéré
[ ] install.ps1 -Mode Audit exécuté
[ ] installation / convergence exécutée
[ ] Ubuntu WSL2 validé
[ ] stack DevOps validée
[ ] terminal / VS Code validés
[ ] qualification matérielle traitée
[ ] mises à jour vérifiées
[ ] sauvegarde de référence créée et vérifiée
```

---

## Si quelque chose échoue

Ne recommence pas toute l'installation par réflexe.

Utilise d'abord :

```powershell
.\install.ps1 -Mode Audit
```

Puis consulte :

```text
logs\
reports\
```

L'orchestrateur est conçu pour corriger un delta plutôt que pour imposer une reconstruction complète à chaque erreur.

Voir [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md).

---

## Si tu dois reconstruire après panne

Utilise le Runbook :

[`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md).

Il couvre le choix entre restauration et réinstallation, le retour de Windows, WSL2, DevOps, les données et la nouvelle sauvegarde de référence.

---

## Règle de sortie

L'installation est terminée lorsque la machine est :

```text
stable
+
compréhensible
+
conforme aux contrats du dépôt
+
validée sur le matériel réel
+
maintenable
+
récupérable
```

Le but n'est pas d'obtenir le plus grand nombre de scripts exécutés, mais une **workstation réellement exploitable et reproductible**.
