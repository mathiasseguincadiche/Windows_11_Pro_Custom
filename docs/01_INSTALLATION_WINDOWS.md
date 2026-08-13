# Installation Windows 11 Pro — guide complet débutant

Ce guide explique comment repartir d'un PC vide ou fraîchement réinstallé et obtenir une base Windows 11 Pro propre **avant** de lancer l'automatisation du dépôt.

Il est volontairement détaillé : lorsqu'une étape est manuelle ou potentiellement dangereuse, elle est explicitement signalée.

> **Règle de sécurité absolue :** aucun script de ce dépôt ne formate les SSD. Le partitionnement et l'installation initiale de Windows restent des opérations manuelles contrôlées par l'utilisateur.

---

## 1. Résultat attendu

À la fin de ce document, la machine doit ressembler à ceci :

```text
Crucial T705 #1
└── Windows 11 Pro
    └── C: NTFS

Crucial T705 #2
└── D: NTFS
    ├── données
    ├── WSL
    └── OpenClaw plus tard

UEFI
├── mode UEFI
├── CSM désactivé
├── Secure Boot actif
├── TPM 2.0 / AMD fTPM actif
├── SVM actif
├── Above 4G Decoding actif
└── Resizable BAR actif
```

Le filesystem Linux WSL sera plus tard contenu dans un fichier VHDX sur `D:`. **Ne crée pas de partition EXT4 sur le deuxième SSD.**

---

## 2. Matériel concerné par ce projet

Configuration cible versionnée dans `config/hardware/target-v5.json` :

- AMD Ryzen 7 7700 ;
- MSI MAG B850M Mortar WiFi ;
- 48 Go DDR5 ;
- Intel Arc B580 ;
- deux Crucial T705 ;
- écran 2560×1440 à environ 240 Hz.

Les commandes du dépôt vérifieront plus tard une partie de ces éléments automatiquement. D'autres points, comme l'emplacement physique des SSD ou la stabilité RAM, restent manuels.

---

## 3. Ce qu'il faut préparer avant l'installation

### Obligatoire

- une clé USB de 8 Go ou plus ;
- une connexion Internet disponible après installation ;
- une licence ou un droit numérique Windows 11 Pro ;
- l'accès à ce dépôt GitHub depuis un autre appareil en cas de besoin ;
- idéalement les identifiants du compte Microsoft utilisés pour l'activation/configuration personnelle.

### Recommandé

Sur un autre support, conserver :

- le pilote réseau/Wi-Fi MSI si Windows ne reconnaissait pas le réseau ;
- le pilote chipset AMD B850 ;
- le pilote Intel Arc ;
- toute clé de récupération ou information importante liée à un chiffrement existant ;
- une copie de tes fichiers personnels si tu réinstalles une machine déjà utilisée.

### À ne pas faire

- télécharger une ISO Windows depuis un site non officiel ;
- télécharger des « driver packs » génériques ;
- utiliser un script de debloat avant que Windows soit installé et validé ;
- modifier PBO/overclocking pendant une reconstruction dont la stabilité n'est pas encore prouvée.

---

## 4. Télécharger Windows 11 depuis Microsoft

Source officielle :

- <https://www.microsoft.com/software-download/windows11>

Pour ce projet, utiliser une **image x64 Windows 11 stable officielle**, pas une Insider Preview.

Deux méthodes sont raisonnables :

### Méthode A — outil Microsoft depuis un autre Windows

Utilise l'outil officiel de création de média Microsoft et crée directement une clé USB d'installation.

C'est la méthode la plus simple pour un débutant disposant déjà d'un PC Windows.

### Méthode B — ISO officielle

Télécharge l'ISO x64 officielle depuis la même page Microsoft.

Microsoft fournit également les informations permettant de vérifier l'intégrité SHA-256 des ISO proposées. Si tu as téléchargé l'ISO manuellement, cette vérification est recommandée.

Sous PowerShell :

```powershell
Get-FileHash .\Windows11.iso -Algorithm SHA256
```

Compare le hash avec celui affiché par Microsoft pour **la même édition/langue de l'ISO**.

---

## 5. Créer la clé USB

### Depuis Windows

La voie la plus simple est l'outil Microsoft.

Rufus peut également écrire une ISO, mais le projet ne dépend d'aucun contournement matériel ou OOBE proposé par des outils tiers. L'objectif est une installation Windows 11 supportée normalement par le matériel.

### Depuis Linux avec Ventoy

Si la clé est déjà préparée avec Ventoy :

1. monte la grande partition `Ventoy` ;
2. copie l'ISO Windows 11 officielle dans cette partition ;
3. démonte proprement la clé ;
4. démarre le PC en mode UEFI sur la clé ;
5. dans le menu Ventoy, sélectionne l'ISO Windows 11.

Ne modifie pas l'ISO et ne contourne pas TPM/Secure Boot : la configuration cible respecte naturellement les exigences Windows 11.

---

## 6. Avant l'installation : BIOS / UEFI

### 6.1 Charger une base saine

Si la machine vient d'être assemblée ou si le BIOS a reçu beaucoup de réglages expérimentaux :

1. entrer dans l'UEFI ;
2. charger les paramètres optimisés/par défaut ;
3. appliquer ensuite uniquement les réglages nécessaires ci-dessous.

### 6.2 Réglages attendus

| Réglage | Cible | Pourquoi |
|---|---|---|
| Boot mode | UEFI | requis pour GPT/Secure Boot |
| CSM / Legacy boot | désactivé | évite le démarrage hérité |
| TPM / AMD fTPM | actif | Windows 11 / sécurité |
| Secure Boot | actif | protection du boot |
| SVM | actif | virtualisation / WSL2 |
| Above 4G Decoding | actif | plateforme GPU moderne |
| Resizable BAR | actif | requis/recommandé pour Intel Arc |

Windows 11 exige notamment UEFI/Secure Boot capable et TPM 2.0. La configuration cible du projet dépasse largement le minimum Windows 11.

### 6.3 RAM 6000 MT/s

La cible du projet est 6000 MT/s **uniquement si stable**.

Pour une réinstallation de dépannage :

- si la mémoire 6000 a déjà été longuement validée sur cette machine, le profil connu comme stable peut être conservé ;
- si tu diagnostiques des crashes, des erreurs mémoire ou une nouvelle version BIOS, reviens temporairement aux paramètres mémoire par défaut, installe/valide Windows, puis revalide 6000 séparément.

Ne mélange pas un diagnostic Windows avec un overclocking mémoire incertain.

---

## 7. BIOS : faut-il le mettre à jour ?

Le dépôt ne flashe **jamais** le BIOS.

Support officiel de la carte mère :

- <https://www.msi.com/Motherboard/MAG-B850M-MORTAR-WIFI/support>

Procédure recommandée :

1. relever la version BIOS actuellement installée ;
2. consulter la page support MSI ;
3. lire les notes de version ;
4. préférer une version stable/non bêta sauf raison précise ;
5. ne flasher que si la mise à jour est pertinente : compatibilité CPU/RAM, sécurité, bug connu, stabilité ou recommandation constructeur.

**Ne mets jamais à jour le BIOS simplement pour « avoir le numéro le plus élevé » au milieu d'un diagnostic stable.**

---

## 8. Sécuriser l'identification des deux SSD

Le PC contient deux Crucial T705 similaires. C'est le moment le plus facile pour sélectionner le mauvais disque.

### Méthode la plus sûre

Si c'est simple et sans risque matériel, désactive temporairement dans l'UEFI ou déconnecte le **deuxième SSD destiné à `D:`** pendant l'installation Windows.

Avantages :

- impossible d'effacer accidentellement le DATA disk ;
- les partitions EFI/Recovery de Windows restent naturellement sur le SSD système ;
- l'identification du disque est évidente.

Après le premier démarrage réussi de Windows, reconnecte/réactive le second SSD.

### Si les deux SSD restent présents

À l'écran de sélection des disques :

- vérifie soigneusement numéro et capacité ;
- ne supprime jamais les partitions d'un disque dont tu n'es pas certain ;
- en cas de doute, annule l'installation et vérifie physiquement/UEFI avant de continuer.

---

## 9. Démarrer sur la clé USB

1. insère la clé ;
2. démarre le PC ;
3. ouvre le Boot Menu MSI ;
4. sélectionne l'entrée **UEFI** correspondant à la clé ;
5. démarre l'installation Windows.

Si la clé apparaît deux fois, choisis l'entrée explicitement UEFI.

---

## 10. Installer Windows 11 Pro

### 10.1 Langue et clavier

Choisis la langue et le clavier réellement utilisés. Ils pourront être modifiés ensuite dans Windows.

### 10.2 Clé produit / édition

Si l'activation numérique est déjà liée au matériel/compte, Windows peut permettre de poursuivre sans saisir immédiatement une clé.

Quand l'édition est demandée, sélectionne **Windows 11 Pro**.

Ne sélectionne pas Home si la licence et le projet ciblent Pro.

### 10.3 Type d'installation

Choisis une **installation personnalisée** pour une installation propre.

### 10.4 Sélection du SSD système

Sur le **T705 destiné à Windows uniquement** :

1. si tu souhaites réellement une réinstallation totalement propre et que les données sont sauvegardées, supprime les anciennes partitions Windows de ce SSD ;
2. obtiens un espace non alloué ;
3. sélectionne cet espace non alloué ;
4. laisse Windows créer automatiquement ses partitions GPT/EFI/MSR/Recovery/Primary.

Ne crée pas manuellement une partition EFI sans besoin particulier.

> **ATTENTION : supprimer une partition détruit les données qu'elle contient. Vérifie le disque avant chaque suppression.**

### 10.5 Premier redémarrage

Après la copie des fichiers :

- laisse le PC redémarrer ;
- si le programme d'installation redémarre à nouveau sur la clé USB, retire la clé ou choisis Windows Boot Manager.

---

## 11. Premier démarrage Windows / OOBE

Suis l'assistant Windows officiel.

Pour un usage personnel, les versions actuelles de Windows 11 Pro peuvent exiger une connexion Internet et un compte Microsoft pendant la configuration initiale. Le projet ne documente pas de contournement non supporté de l'OOBE.

Pendant l'OOBE :

- vérifie le bon clavier ;
- choisis un nom de machine clair ;
- configure l'authentification ;
- lis les options de confidentialité au lieu de cliquer mécaniquement ;
- termine complètement l'arrivée sur le bureau.

Les réglages du dépôt seront appliqués **après** la création d'un Windows fonctionnel et vérifiable.

---

## 12. Vérifications immédiates après le bureau

Ouvre :

```text
Paramètres -> Système -> Activation
```

Vérifie :

- Windows 11 Pro ;
- activation correcte ;
- heure/fuseau corrects ;
- Internet fonctionnel ;
- résolution écran correcte au minimum.

Commande utile :

```powershell
winver
```

---

## 13. Windows Update — premier passage

Avant les optimisations du dépôt, termine un premier cycle Windows Update :

```text
Paramètres -> Windows Update -> Rechercher des mises à jour
```

Installe les mises à jour normales proposées, redémarre si demandé, puis recherche à nouveau jusqu'à obtenir un état stable.

Pour les **drivers optionnels**, ne clique pas automatiquement sur tout : la stratégie du projet préfère les sources constructeur pour le chipset AMD et le GPU Intel Arc.

Le gestionnaire V11 du dépôt prendra ensuite en charge la maintenance régulière.

---

## 14. Pilote chipset AMD B850

Source officielle AMD :

- <https://www.amd.com/en/support/downloads/drivers.html/chipsets/am5/b850.html>

AMD recommande d'utiliser un système Windows à jour avant d'installer son package chipset.

Procédure :

1. télécharger le package **AMD Chipset Drivers** pour B850 / Windows 11 64 bits ;
2. lancer l'installateur ;
3. conserver les composants recommandés par AMD sauf besoin spécifique ;
4. redémarrer si demandé.

Ne télécharge pas de chipset driver depuis un agrégateur tiers.

---

## 15. Pilote Intel Arc B580

Source officielle Intel :

- <https://www.intel.com/content/www/us/en/products/sku/241598/intel-arc-b580-graphics/downloads.html>

Intel Arc B-Series bénéficie de Resizable BAR ; le projet vérifie donc manuellement ReBAR/Above 4G côté UEFI.

Procédure :

1. télécharger le pilote Windows officiel Intel Arc B-Series ;
2. installer le pilote ;
3. redémarrer si nécessaire ;
4. vérifier que l'Arc B580 apparaît sans erreur dans le Gestionnaire de périphériques ;
5. régler ensuite l'écran à sa résolution/fréquence cible si disponible.

Le numéro exact du pilote n'est pas figé dans ce guide car il évolue plus vite que le dépôt.

---

## 16. Pilotes MSI : LAN / Wi-Fi / Bluetooth / audio

Support officiel :

- <https://www.msi.com/Motherboard/MAG-B850M-MORTAR-WIFI/support>

Ordre pratique :

1. vérifier d'abord le Gestionnaire de périphériques ;
2. laisser Windows Update gérer ce qu'il reconnaît proprement ;
3. pour un périphérique absent/mal reconnu ou pour un driver spécifique carte mère, utiliser MSI ;
4. privilégier LAN/Wi-Fi/Bluetooth/audio nécessaires au fonctionnement réel ;
5. éviter d'installer des utilitaires OEM simplement parce qu'ils existent.

Le projet ne dépend pas de MSI Center pour fonctionner.

---

## 17. Vérifier le Gestionnaire de périphériques

Ouvre :

```text
Win + X -> Gestionnaire de périphériques
```

Objectif :

- aucun « périphérique inconnu » ;
- aucun triangle jaune inattendu ;
- Arc B580 détectée ;
- réseau/Wi-Fi/Bluetooth fonctionnels ;
- audio fonctionnel ;
- stockage visible.

Si un périphérique est inconnu, résous cela **avant** de passer aux optimisations.

---

## 18. Reconnecter et préparer le deuxième Crucial T705

Si tu avais désactivé/déconnecté le deuxième SSD, éteins proprement le PC et reconnecte/réactive-le.

Dans Windows :

```text
Win + X -> Gestion des disques
```

Pour le deuxième T705 destiné aux données :

1. initialise-le en **GPT** s'il est neuf ;
2. crée un volume simple ;
3. formate-le en **NTFS** ;
4. attribue la lettre **D:** ;
5. un label comme `DATA` est recommandé pour le reconnaître rapidement.

Architecture attendue :

```text
C: -> Windows 11 Pro
D: -> DATA / WSL / OpenClaw / ISO / exports
```

Ne formate pas `D:` en EXT4.

---

## 19. Vérifier C: et D: en PowerShell

Ouvre PowerShell :

```powershell
Get-Volume -DriveLetter C,D | Format-Table DriveLetter,FileSystem,FileSystemLabel,HealthStatus,Size,SizeRemaining
```

Résultat attendu :

```text
C  NTFS  ... Healthy
D  NTFS  ... Healthy
```

Vérifier les disques :

```powershell
Get-Disk | Format-Table Number,FriendlyName,PartitionStyle,HealthStatus,OperationalStatus,Size
```

Le disque système doit utiliser GPT.

---

## 20. Vérifier Secure Boot et TPM

### Secure Boot

PowerShell administrateur :

```powershell
Confirm-SecureBootUEFI
```

Résultat attendu :

```text
True
```

### TPM

```powershell
Get-Tpm
```

Le TPM doit être présent/prêt ; Windows 11 exige TPM 2.0.

Tu peux aussi utiliser :

```text
Win + R -> tpm.msc
```

---

## 21. Vérifier la virtualisation

WSL2 nécessite la virtualisation firmware.

Vérifie dans le Gestionnaire des tâches :

```text
Performances -> Processeur -> Virtualisation : Activée
```

Ou avec :

```powershell
systeminfo
```

Le firmware cible utilise SVM côté AMD.

---

## 22. Vérifier l'écran

Après installation du driver Arc :

```text
Paramètres -> Système -> Affichage -> Affichage avancé
```

Pour la cible du projet :

```text
2560 x 1440
~240 Hz
```

Ne force pas une fréquence non proposée par Windows/driver/écran.

---

## 23. Obtenir le dépôt sur un Windows vierge

Une installation Windows propre **ne doit pas supposer que Git for Windows est déjà installé**.

### Méthode recommandée débutant — Download ZIP

1. ouvre la page GitHub du dépôt dans le navigateur ;
2. `Code` -> `Download ZIP` ;
3. extrais l'archive dans un dossier simple, par exemple :

```text
C:\Users\<user>\Documents\Windows_11_Pro_Custom
```

4. ouvre PowerShell dans ce dossier.

### Méthode Git — seulement si Git est déjà disponible

```powershell
git clone https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom.git
cd Windows_11_Pro_Custom
```

Le Git utilisé quotidiennement pour les projets DevOps sera ensuite celui d'Ubuntu WSL.

---

## 24. Première exécution : Audit seulement

Ouvre **PowerShell en administrateur** dans le dossier du dépôt.

Autoriser les scripts uniquement pour cette session :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

Puis :

```powershell
.\install.ps1 -Mode Audit
```

L'Audit observe la machine et génère des preuves. Il ne doit pas être confondu avec l'installation complète.

Contrôle notamment :

- préflight Windows ;
- état machine ;
- stockage ;
- applications ;
- réglages Windows ;
- WSL ;
- workstation ;
- Defender ;
- inventaire matériel ;
- OpenClaw s'il existe déjà.

Si l'Audit détecte un problème fondamental — mauvais filesystem, stockage absent, configuration incohérente — **corrige ce problème avant Apply**.

---

## 25. Le menu interactif

Après l'Audit, le moyen le plus simple de poursuivre est :

```powershell
.\menu.ps1
```

ou double-clic :

```text
START_MENU.cmd
```

Pour une reconstruction complète, choisis :

```text
1. Installation complète
```

Cela route vers :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

---

## 26. Pourquoi `FullInstall` peut demander des actions manuelles

`FullInstall` active notamment :

- installation DevOps ;
- validation WSL ;
- validation DevOps ;
- qualification matérielle ;
- OpenClaw/OpenRouter.

Certaines preuves matérielles ne peuvent pas être inventées par un script :

- ReBAR réellement actif dans l'UEFI ;
- Above 4G ;
- emplacement physique M2_1/M2_2 ;
- refroidissement des T705 ;
- stabilité mémoire 6000 ;
- revue BIOS stable ;
- revue des drivers constructeur.

Le script peut donc demander une saisie guidée avant de déclarer `V5 HARDWARE READY`.

---

## 27. Après installation de WSL

Le contrat cible est :

```text
Ubuntu 26.04
D:\WSL\Ubuntu-DevOps
```

Au premier lancement Ubuntu, si Windows/WSL demande de créer l'utilisateur Linux, fais-le puis reviens au processus d'installation.

Les projets DevOps doivent ensuite être placés dans :

```bash
mkdir -p ~/projects ~/labs ~/repositories
```

Évite `/mnt/c` et `/mnt/d` pour les projets Linux actifs.

Guide pédagogique complet : [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md).

---

## 28. Après installation : validation globale

Une fois les actions manuelles terminées :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware -ValidateWsl -ValidateDevOps -ValidateOpenClawAI
```

Ou utilise l'option de vérification du menu V12.

Ne considère pas la machine comme « terminée » simplement parce que les programmes sont visibles dans le menu Démarrer : la validation doit vérifier les contrats réels.

---

## 29. Créer le Golden Backup

Quand Windows, drivers, WSL, DevOps et applications sont réellement validés, connecte un **disque USB NTFS séparé**.

Exemple si la cible est `E:` :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
```

Puis :

```powershell
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
```

N'utilise pas le SSD interne `D:` comme unique sauvegarde d'une machine dont `D:` fait lui-même partie des données à protéger.

Guide : [`18_BACKUP_DISASTER_RECOVERY_V7.md`](18_BACKUP_DISASTER_RECOVERY_V7.md).

---

## 30. Maintenance après installation

Pour les mises à jour régulières :

```powershell
.\update.ps1 -Mode Audit
.\update.ps1 -Mode Apply
```

ou choisis **3 — Mises à jour complètes** dans le menu.

V11 met à jour ce qu'il peut de manière contrôlée, mais ne flashe jamais le BIOS et n'installe pas les drivers Windows Update facultatifs par défaut.

---

## 31. Checklist finale d'une installation propre

```text
[ ] Windows 11 Pro activé
[ ] C: = NTFS sur T705 système
[ ] D: = NTFS sur deuxième T705
[ ] UEFI / CSM off
[ ] Secure Boot actif
[ ] TPM 2.0 actif
[ ] SVM actif
[ ] Above 4G actif
[ ] ReBAR actif
[ ] Windows Update stabilisé
[ ] AMD chipset installé
[ ] Intel Arc driver installé
[ ] aucun périphérique inconnu
[ ] écran à la résolution/fréquence attendue
[ ] install.ps1 -Mode Audit exécuté
[ ] installation complète exécutée
[ ] WSL2/Ubuntu validé
[ ] stack DevOps validée
[ ] terminal/VS Code validés
[ ] sauvegarde V7 créée et vérifiée
```

---

## 32. Sources officielles à utiliser

Toujours préférer les sources constructeur :

- Microsoft — Windows 11 : <https://www.microsoft.com/software-download/windows11>
- Microsoft — exigences Windows 11 : <https://support.microsoft.com/windows/windows-11-system-requirements>
- Microsoft — Secure Boot : <https://support.microsoft.com/windows/windows-11-and-secure-boot>
- Microsoft — TPM 2.0 : <https://support.microsoft.com/windows/enable-tpm-2-0-on-your-pc>
- MSI — MAG B850M Mortar WiFi : <https://www.msi.com/Motherboard/MAG-B850M-MORTAR-WIFI/support>
- AMD — chipset B850 : <https://www.amd.com/en/support/downloads/drivers.html/chipsets/am5/b850.html>
- Intel — Arc B580 : <https://www.intel.com/content/www/us/en/products/sku/241598/intel-arc-b580-graphics/downloads.html>

Les versions exactes de BIOS et drivers changent. Le principe du projet est donc de **documenter la source officielle et la méthode de validation**, pas de graver un ancien numéro de version dans le Runbook.
