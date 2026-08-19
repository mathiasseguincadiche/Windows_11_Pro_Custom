# Runbook — réinstallation et reconstruction complète de la workstation

Ce Runbook sert quand la machine doit être **reconstruite après une panne, un remplacement de disque, une réinstallation volontaire ou une perte importante de configuration**.

Il ne suppose pas que la meilleure réponse est toujours « réinstaller Windows ». La première étape consiste à choisir entre réparation, restauration et reconstruction.

> **Frontière de sécurité :** ce dépôt peut préparer, auditer, converger et vérifier la workstation, mais il ne formate jamais automatiquement les SSD et ne déclenche jamais une restauration bare-metal destructive sans décision humaine.

Pour une première installation sans incident, utiliser [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md).

Pour comprendre la stratégie de sauvegarde, utiliser [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

# Phase 0 — qualifier l'incident

Avant de toucher aux disques, réponds à ces questions :

```text
Windows démarre-t-il ?
Les données C: sont-elles accessibles ?
Les données E: sont-elles accessibles ?
WSL2 démarre-t-il ?
Le VHDX Ubuntu existe-t-il ?
Une image Windows validée existe-t-elle ?
Un export WSL validé existe-t-il ?
Le disque de sauvegarde externe est-il disponible ?
Le problème est-il logiciel, système ou matériel ?
```

Ne reformate pas une machine dont le problème pourrait être corrigé par un rollback ou une restauration ciblée.

---

## Choisir la bonne stratégie

### Cas A — Windows démarre et la machine est seulement incohérente

Commence par :

```powershell
.\install.ps1 -Mode Audit
```

Avant toute planification stricte, vérifier l'identité V25 :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Verify
```

Si la baseline est absente ou si la topologie a changé volontairement, suivre
[`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md)
et ne jamais remplacer la référence pour masquer une alerte.

Puis, si les écarts sont compris :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Le mode `PlanOnly` permet de voir le plan avant toute mutation.

Si le plan est cohérent :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

Une réinstallation Windows n'est pas nécessaire si l'orchestrateur peut faire converger la machine.

### Cas B — un réglage géré récemment a cassé le poste

Si l'état précédent est connu et rollbackable :

```powershell
.\install.ps1 -Mode Rollback
```

Le rollback concerne les composants gérés pour lesquels un état initial fiable existe. Il ne remplace pas une restauration complète.

### Cas C — Windows est endommagé mais une image validée existe

Évalue la restauration Windows à partir du support de sauvegarde externe et de WinRE.

Une restauration bare-metal reste manuelle.

### Cas D — seul WSL2 est endommagé

Si un export VHDX validé existe, restaure d'abord Ubuntu **sous un nom distinct**, par exemple :

```text
Ubuntu-Restore
```

Ne supprime pas la distribution active avant d'avoir vérifié la copie restaurée.

### Cas E — disque remplacé ou réinstallation complète souhaitée

Suis les phases suivantes du Runbook.

---

# Phase 1 — protéger ce qui est encore récupérable

Si les disques sont accessibles, sauvegarde avant toute opération destructrice.

Priorités :

```text
données personnelles
projets non poussés sur Git
clés SSH
fichiers de configuration locaux
secrets / credentials
VHDX WSL ou export disponible
données de projets externes importantes
documents non synchronisés
```

Pour les données applicatives appartenant à un projet externe, conserve-les si nécessaire mais utilise ensuite la procédure de restauration de ce projet. `Windows_11_Pro_Custom` ne possède pas leur reconstruction fonctionnelle.

Ne mets jamais les secrets dans le dépôt Git pour les « sauver temporairement ».

Si une sauvegarde de référence existe déjà, **ne l'écrase pas** avant d'avoir terminé la reconstruction.

---

# Phase 2 — vérifier le matériel avant de réinstaller

Une panne logicielle supposée peut être causée par un problème matériel.

Avant une reconstruction complète, vérifie :

- SSD visibles dans l'UEFI ;
- température et refroidissement plausibles ;
- RAM détectée ;
- absence d'erreurs matérielles connues ;
- câble/écran/périphériques essentiels ;
- stabilité du BIOS ;
- alimentation correcte.

Si la machine présente des crashs aléatoires, réduis les variables expérimentales :

```text
RAM -> paramètres sûrs
CPU -> stock
GPU -> pas d'OC/undervolt expérimental
BIOS -> base stable connue
```

La qualification complète est documentée dans [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

---

# Phase 3 — préparer le média Windows

Utilise une image Windows 11 officielle et une clé USB fiable.

Depuis Linux, Ventoy peut être utilisé si la clé est déjà préparée. Depuis Windows, l'outil Microsoft de création de média est la méthode la plus simple.

L'objectif est une installation supportée normalement : aucun contournement TPM/Secure Boot n'est nécessaire sur cette configuration.

---

# Phase 4 — sécuriser les deux SSD

La workstation utilise deux Crucial T705 similaires :

```text
T705 #1 -> C: -> Windows 11 Pro
T705 #2 -> E: -> données / WSL / données lourdes
```

La meilleure protection contre une erreur de sélection est de déconnecter ou désactiver temporairement le SSD `E:` pendant l'installation Windows si cela peut être fait sans risque.

Sinon, vérifie numéro et capacité à chaque suppression de partition.

> Une erreur de disque au moment du partitionnement est irréversible sans sauvegarde.

---

# Phase 5 — vérifier l'UEFI

Réglages attendus :

| Réglage | Cible |
| --- | --- |
| Boot | UEFI |
| CSM | désactivé |
| Secure Boot | actif |
| TPM / AMD fTPM | actif |
| SVM | actif |
| Above 4G Decoding | actif |
| Resizable BAR | actif |

Le dépôt ne les modifie pas automatiquement.

Si la RAM est en cours de diagnostic, privilégie une configuration stable avant de retenter 6000 MT/s.

---

# Phase 6 — réinstaller Windows 11 Pro

Démarre sur le média UEFI puis effectue une installation personnalisée sur le **SSD système uniquement**.

Pour une reconstruction totalement propre :

1. confirme que les données importantes sont sauvegardées ;
2. sélectionne le bon T705 ;
3. supprime uniquement les anciennes partitions Windows voulues ;
4. laisse Windows recréer automatiquement GPT/EFI/MSR/Recovery/Primary ;
5. installe Windows 11 Pro.

Après le premier redémarrage, démarre sur Windows Boot Manager.

---

# Phase 7 — stabiliser Windows avant le dépôt

Une fois sur le bureau :

1. vérifier activation et édition Windows 11 Pro ;
2. vérifier heure/fuseau/réseau ;
3. effectuer Windows Update ;
4. redémarrer si nécessaire ;
5. installer le chipset AMD ;
6. installer le pilote Intel Arc ;
7. compléter les pilotes MSI réellement nécessaires ;
8. vérifier le Gestionnaire de périphériques.

Ne lance pas les optimisations tant que des périphériques essentiels restent inconnus ou instables.

---

# Phase 8 — reconstruire `E:`

Si le second SSD est intact, ne le reformate pas inutilement.

S'il a été remplacé ou doit réellement être recréé :

```text
GPT
└── E: NTFS
```

Architecture logique :

```text
E:\
├── DATA\
├── WSL\
│   ├── Ubuntu-DevOps\
│   └── swap\
├── ISO\
└── exports\
```

Aucune partition EXT4 physique n'est nécessaire.

Les projets externes peuvent utiliser d'autres dossiers sur `E:` mais ces emplacements ne sont pas créés ni gouvernés par ce dépôt.

Guide : [`03_STOCKAGE.md`](03_STOCKAGE.md).

---

# Phase 9 — récupérer le dépôt

Installe Git si nécessaire puis clone :

```powershell
mkdir C:\Dev -ErrorAction SilentlyContinue
cd C:\Dev
git clone https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom.git
cd Windows_11_Pro_Custom
```

Avant toute mutation :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Mode Audit
```

L'audit doit être conservé comme premier état factuel de la reconstruction.

---

# Phase 10 — qualifier l'identité physique du stockage

Avant le premier plan strict de la reconstruction :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Audit
```

Comparer le rapport avec la topologie attendue. Si la baseline V25 a été restaurée
par le Golden Backup et correspond, la vérifier :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Verify
```

Si la baseline est légitimement absente après réinstallation, contrôler
humainement `C:` et `E:`, puis l'enrôler explicitement et la vérifier selon
[`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md).

---

# Phase 11 — prévisualiser la convergence

Calcule le plan complet :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Relis le plan.

Le résultat attendu n'est pas forcément « tout installer » : une machine partiellement restaurée peut déjà contenir des éléments conformes.

Le moteur doit distinguer :

```text
DÉJÀ OK
À FAIRE
ACTION REQUISE
KO
```

Guide : [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md).

---

# Phase 12 — appliquer la configuration actuelle

Si le plan est cohérent :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

Ou utilise le centre de contrôle :

```text
START_MENU.cmd
```

Puis **Installation complète**.

Le processus peut nécessiter plusieurs passages lorsque Windows ou WSL exige un redémarrage ou une création d'utilisateur.

Ne considère pas un redémarrage nécessaire comme un échec : traite l'action puis relance l'audit/convergence.

`-FullInstall` ne déclenche aucun projet externe.

---

# Phase 13 — WSL2 / Ubuntu

Le contrat actuel est :

```text
Ubuntu 26.04
E:\WSL\Ubuntu-DevOps
HOME ext4
```

Si Ubuntu doit être recréé, crée un utilisateur Linux normal, puis laisse le dépôt installer/converger la configuration.

Après une modification de `.wslconfig` :

```powershell
wsl --shutdown
wsl -d Ubuntu
```

Dans Ubuntu :

```bash
whoami
nproc
free -h
swapon --show
ps -p 1 -o comm=
findmnt -T "$HOME"
```

Guide : [`06_WSL2.md`](06_WSL2.md).

---

# Phase 14 — restaurer un WSL sauvegardé

Si un VHDX sauvegardé existe, privilégie une restauration parallèle.

Principe :

```text
Ubuntu actuel
     +
Ubuntu-Restore importé
     ↓
validation indépendante
     ↓
choix humain
```

Vérifie la copie restaurée avant toute suppression de l'ancienne distribution :

- utilisateur ;
- projets ;
- permissions ;
- Docker ;
- outils DevOps ;
- fichiers personnels ;
- intégrité attendue.

Ne lance jamais par automatisme :

```powershell
wsl --unregister Ubuntu
```

Cette commande détruit la distribution ciblée.

---

# Phase 15 — stack DevOps

Applique/valide :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

Puis :

```powershell
wsl --shutdown
.\install.ps1 -Mode Verify -ValidateWsl -ValidateDevOps
```

La stack attendue comprend Docker, Kubernetes, Terraform, Ansible, AWS CLI, GitHub CLI et les outils qualité définis par le dépôt.

Guide : [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md).

---

# Phase 16 — VS Code, Windows Terminal et accès distants

Vérifie que :

- PowerShell 7 fonctionne ;
- Windows Terminal expose `PowerShell 7 - DevOps` comme profil par défaut ;
- `Ubuntu - DevOps` ouvre correctement la distribution `Ubuntu` ;
- Starship PowerShell et JetBrainsMono Nerd Font sont conformes ;
- VS Code WSL ouvre les projets sous `/home/<user>/...` ;
- Remote - SSH fonctionne si nécessaire ;
- les configurations SFTP/FTP personnelles ne publient aucun secret.

Validation ciblée :

```powershell
.\scripts\windows\31_windows_terminal.ps1 -Mode Verify
```

Le terminal et la stack sont documentés dans [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md).

---

# Phase 17 — restaurer les données personnelles

Restaure les données **après** avoir stabilisé le système de base lorsque c'est possible.

Ordre conseillé :

```text
workstation stable
   ↓
profil / documents
   ↓
projets non présents dans Git
   ↓
clés et secrets depuis leur stockage sécurisé
   ↓
données applicatives
   ↓
projets externes, chacun avec sa propre procédure
```

Évite de recopier en bloc des anciens dossiers système ou caches qui pourraient réintroduire le problème initial.

---

# Phase 18 — projets externes

Une fois la workstation Windows/WSL2/DevOps reconstruite et validée, les projets externes peuvent être restaurés ou réinstallés séparément.

Pour OpenClaw/OpenRouter, utiliser exclusivement :

```text
mathiasseguincadiche/openclaw_openrouter
```

Ce dépôt possède l'installation OpenClaw, la configuration OpenRouter, `clawops`, Gateway, modèles, agents, runtime lock et les validations de sa plateforme.

`Windows_11_Pro_Custom` ne crée pas son arborescence, ne clone pas son dépôt, ne déclenche pas son installateur et n'expose aucun `ValidateOpenClawAI`.

Guide de frontière : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

# Phase 19 — validation matérielle

Une réinstallation Windows ne prouve pas que le BIOS, la RAM ou le GPU sont correctement configurés.

Lance :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

Puis renseigne les contrôles manuels si nécessaire :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Record -Interactive
```

Guide : [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

---

# Phase 20 — validation globale

Commande recommandée :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

La validation doit reposer sur l'état réel, pas sur le fait que le script d'installation a été lancé.

La validation d'un projet externe s'effectue ensuite dans son propre dépôt et ne modifie pas le verdict de la workstation.

Guide : [`11_VALIDATION.md`](11_VALIDATION.md).

---

# Phase 21 — maintenance après reconstruction

Audite d'abord :

```powershell
.\update.ps1 -Mode Audit
```

Puis, si la situation est claire :

```powershell
.\update.ps1 -Mode Apply
```

Enfin :

```powershell
.\update.ps1 -Mode Verify
```

Le gestionnaire couvre Windows Update, WinGet, WSL, Ubuntu, outils DevOps épinglés et extensions VS Code sans forcer un reboot ni un flash firmware.

Il ne met pas à jour les projets externes.

Guide : [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

# Phase 22 — créer une nouvelle sauvegarde de référence

Ne remplace pas immédiatement l'ancienne sauvegarde validée.

Quand la reconstruction est stable et réellement vérifiée, crée une nouvelle sauvegarde sur un disque USB NTFS distinct :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive F:
```

Puis :

```powershell
.\install.ps1 -BackupAction Verify -BackupTargetDrive F:
```

Et, pour confirmer que le plan de reprise peut être généré :

```powershell
.\install.ps1 -BackupAction RestorePlan -BackupTargetDrive F:
```

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

# Phase 23 — contrôles finaux

Checklist :

```text
[ ] Windows 11 Pro activé
[ ] aucun périphérique inconnu
[ ] chipset AMD installé
[ ] Intel Arc fonctionnelle
[ ] Secure Boot / TPM / SVM corrects
[ ] ReBAR / Above 4G vérifiés
[ ] C: NTFS correct
[ ] E: NTFS correct
[ ] WSL2 Ubuntu démarre
[ ] HOME Linux sur ext4
[ ] ressources WSL conformes
[ ] Docker fonctionnel
[ ] Terraform / Ansible / kubectl / Helm disponibles
[ ] VS Code WSL fonctionnel
[ ] Windows Terminal / PowerShell 7 / Starship fonctionnels
[ ] PowerShell 7 - DevOps est le profil Windows Terminal par défaut
[ ] Ubuntu - DevOps ouvre Ubuntu WSL2
[ ] validations matérielles traitées
[ ] mises à jour vérifiées
[ ] données restaurées
[ ] secrets non présents dans Git
[ ] backup externe créé et vérifié
```

---

# Si la reconstruction échoue à mi-parcours

Ne recommence pas automatiquement depuis le début.

Relance :

```powershell
.\install.ps1 -Mode Audit
```

Puis consulte :

```text
logs\
reports\
```

Le dépôt est conçu pour **reprendre à partir de l'état réel**.

Une étape déjà conforme doit rester conforme et ne pas être refaite inutilement.

---

# Ce que le Runbook ne fait jamais automatiquement

```text
formatage SSD               NON
flash BIOS                  NON
PBO / OC                    NON
RAM 6000 forcée             NON
Defender désactivé          NON
reboot forcé                NON
wsl --unregister actif      NON
bare-metal restore          NON
secret vers Git             NON
installation projet externe NON
```

Ces limites protègent la machine pendant un moment où le risque d'erreur est déjà élevé.

---

# Ordre de confiance pendant un incident

En cas de contradiction :

1. **état réel de la machine** ;
2. configurations/manifests actuels ;
3. scripts actuels ;
4. documentation actuelle ;
5. changelog et historique Git.

Un ancien comportement documenté dans l'historique ne doit jamais l'emporter sur le contrat actuel de `main`.

---

# Résultat attendu

La reconstruction est terminée lorsque :

```text
Windows est stable
+
le matériel est qualifié
+
WSL2 est conforme
+
la stack DevOps fonctionne
+
Windows Terminal est conforme
+
les données utiles sont restaurées
+
la machine est vérifiée
+
une nouvelle sauvegarde externe est validée
```

Le but du Runbook n'est pas seulement de « remettre Windows ». Il doit rendre à nouveau disponible **la workstation complète**, avec ses frontières Windows/Linux, ses outils, ses preuves et sa capacité de reprise future.
