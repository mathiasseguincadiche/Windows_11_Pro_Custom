# Windows 11 Pro Custom

Workstation **Windows 11 Pro** reproductible, orientée **DevOps/Ops**, conçue pour être installée, auditée, mise à jour, sauvegardée, restaurée et revalidée sans dépendre de réglages « magiques » faits à la main.

Le dépôt cible une machine précise : Ryzen 7 7700, MSI MAG B850M Mortar WiFi, 48 Go DDR5, Intel Arc B580 et deux SSD Crucial T705. Il reste toutefois structuré comme un vrai projet d'infrastructure : état observé, configurations versionnées, scripts idempotents, journaux, preuves et rollback lorsque cela est sûr.

> **Tu débutes ?** Commence par [`docs/README.md`](docs/README.md), puis suis [`docs/01_INSTALLATION_WINDOWS.md`](docs/01_INSTALLATION_WINDOWS.md). Pour une reconstruction complète après panne ou réinstallation, utilise [`docs/13_RUNBOOK_REINSTALLATION.md`](docs/13_RUNBOOK_REINSTALLATION.md).

---

## Objectif du projet

Le résultat attendu est une workstation où les rôles sont clairement séparés :

```text
Windows 11 Pro
├── interface graphique / gaming / applications
├── PowerShell 7
├── VS Code
├── WezTerm
├── Windows Update / WinGet
├── sauvegarde Windows
└── WSL2
    └── Ubuntu 26.04
        ├── Bash DevOps
        ├── Docker Engine
        ├── Kubernetes / Helm
        ├── Terraform / Ansible
        ├── AWS CLI / GitHub CLI
        ├── outils qualité
        └── projets Linux dans /home/<user>/...
```

Le dépôt ne cherche pas à transformer Windows en distribution Linux. Windows reste l'hôte ; Linux DevOps vit dans WSL2.

---

## Point d'entrée recommandé

### Le plus simple : le menu interactif V12

Sous Windows :

```text
START_MENU.cmd
```

ou depuis PowerShell / WezTerm :

```powershell
.\menu.ps1
```

Le centre de contrôle affiche :

```text
1. Installation complète
2. Installation / réparation des logiciels
3. Mises à jour complètes
4. Sauvegarde
5. Restauration / rollback
6. Audit et diagnostic complet
7. Vérification de conformité
8. Composants spécifiques
9. Journaux et rapports
10. Aide
0. Quitter
```

Le menu ne duplique aucune logique : il appelle les orchestrateurs existants et gère l'élévation UAC quand elle est réellement nécessaire.

Guide : [`docs/23_INTERACTIVE_CONTROL_CENTER_V12.md`](docs/23_INTERACTIVE_CONTROL_CENTER_V12.md).

---

## Architecture de stockage

```text
Crucial T705 #1
└── C: NTFS
    ├── Windows 11 Pro
    ├── applications Windows
    └── profil utilisateur

Crucial T705 #2
└── D: NTFS
    ├── données
    ├── D:\WSL\Ubuntu-DevOps
    ├── D:\WSL\swap\wsl-swap.vhdx
    ├── D:\AI\OpenClaw
    ├── ISO
    └── exports temporaires

Disque USB NTFS séparé
└── Golden Backup V7
```

Il n'existe **aucune partition EXT4 physique** prévue par le projet. Le filesystem Linux est contenu dans le VHDX de WSL2 stocké sur `D:`.

Pour les outils Linux, les projets actifs restent dans le filesystem Linux :

```text
/home/<user>/projects
/home/<user>/labs
/home/<user>/repositories
```

`/mnt/c` et `/mnt/d` ne sont pas les emplacements de travail DevOps recommandés.

Architecture détaillée : [`docs/00_ARCHITECTURE.md`](docs/00_ARCHITECTURE.md).

---

## Matériel cible

| Composant | Cible |
|---|---|
| CPU | AMD Ryzen 7 7700 — 8 cœurs / 16 threads |
| Carte mère | MSI MAG B850M Mortar WiFi |
| RAM | 48 Go DDR5 — cible 6000 MT/s uniquement si stable |
| GPU | Intel Arc B580 12 Go |
| SSD système | Crucial T705 PCIe 5.0 |
| SSD DATA/WSL | Crucial T705 PCIe 5.0 |
| AIO | DeepCool LD240WH |
| Alimentation | Corsair RM650e 650 W |
| Boîtier | ASUS Prime AP201 |
| Écran cible | 2560×1440, ~240 Hz |

La politique V5 reste prudente :

```text
Ryzen 7 7700       -> stock / Precision Boost 2
DDR5               -> 6000 seulement si stabilité démontrée
Arc B580            -> ReBAR / Above 4G contrôlés manuellement
T705                -> santé / GPT / filesystem validés
Plan alimentation   -> Balanced
```

Le dépôt ne flashe jamais le BIOS et ne modifie jamais automatiquement PBO, fréquences mémoire, ReBAR ou paramètres M.2.

Guide : [`docs/15_HARDWARE_QUALIFICATION_V5.md`](docs/15_HARDWARE_QUALIFICATION_V5.md).

---

## WSL2 cible

Contrat actuel :

```text
Distribution : Ubuntu
Version      : 26.04
Codename     : resolute
Emplacement  : D:\WSL\Ubuntu-DevOps
HOME Linux   : ext4 dans le VHDX WSL
```

### Profil standard

```text
20 Go RAM
8 threads
8 Go swap
networkingMode=mirrored
DNS tunneling actif
firewall WSL/Hyper-V actif
autoMemoryReclaim=gradual
sparseVhd=true
nestedVirtualization=false
```

### Profil lab-heavy

```text
28 Go RAM
12 threads
12 Go swap
```

### Profil nat-fallback

Même budget que `standard`, mais réseau NAT pour dépannage.

Apprentissage WSL2 : [`docs/16_WSL2_GUIDE_COMPLET.md`](docs/16_WSL2_GUIDE_COMPLET.md).

Tuning spécifique : [`docs/17_WSL2_TUNING_V6.md`](docs/17_WSL2_TUNING_V6.md).

---

## Stack DevOps Linux

La stack WSL couvre notamment :

- Docker Engine, Compose et Buildx ;
- kubectl ;
- Helm ;
- Minikube ;
- kind ;
- Terraform ;
- AWS CLI v2 ;
- Ansible Core ;
- GitHub CLI ;
- Trivy ;
- ShellCheck ;
- shfmt ;
- terraform-docs ;
- actionlint ;
- yq ;
- TFLint.

Les outils sensibles à la reproductibilité utilisent la matrice versionnée :

```text
config/devops/tool-versions.env
```

Le gestionnaire de mises à jour V11 ne remplace pas ces versions par `latest` de manière aveugle.

---

## Terminal DevOps V10

WezTerm est le terminal Windows principal :

```text
WezTerm
├── Ubuntu DevOps / Bash  <- défaut
└── PowerShell 7          <- secondaire
```

VS Code utilise le même Bash WSL afin d'obtenir une expérience cohérente.

Le profil fournit :

- Starship ;
- fzf ;
- zoxide ;
- eza ;
- bat ;
- fd ;
- ripgrep ;
- alias Git/Docker/Kubernetes/Helm/Terraform/Ansible/AWS ;
- complétions DevOps.

Guide : [`docs/21_DEVOPS_TERMINAL_V10.md`](docs/21_DEVOPS_TERMINAL_V10.md).

---

## Applications Windows

Applications automatisables par WinGet :

```text
Visual Studio Code
PowerShell 7
JetBrainsMono Nerd Font
VLC
Notion
Firefox
Brave
FileZilla
WezTerm
LibreOffice
Steam
Notepad++
draw.io
Bitwarden
```

Applications volontairement manuelles car aucune automatisation WinGet n'est considérée assez fiable dans le manifeste actuel :

```text
MarkText
Microsoft Office
PDFgear
Files
```

Source de vérité :

```text
manifests/winget/apps-core.json
```

---

## Orchestration V9 : machine-first et idempotence

`install.ps1` ne suppose pas qu'une étape est à faire parce qu'elle figure dans une liste.

Le principe est :

```text
Découvrir l'état réel
        ↓
Verify
        ↓
DEJA_OK ou A_FAIRE
        ↓
Apply seulement si nécessaire
        ↓
Re-Verify
        ↓
preuve / log / verdict
```

Modes :

```powershell
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Apply
.\install.ps1 -Mode Verify
.\install.ps1 -Mode Rollback
```

Installation complète :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

`-FullInstall` inclut WSL/DevOps, validations matérielles/WSL/DevOps et OpenClaw selon le contrat du dépôt.

Prévisualisation sans mutation après la découverte :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Documentation : [`docs/21_ORCHESTRATION_IDEMPOTENCE_V9.md`](docs/21_ORCHESTRATION_IDEMPOTENCE_V9.md).

---

## Windows Optimization V4 + Responsiveness V8

Le dépôt applique uniquement des changements versionnés, réversibles et vérifiés.

Profils V4 :

```text
standard  <- défaut
privacy   <- opt-in
gaming    <- opt-in
optional  <- opt-in
```

Exemple :

```powershell
.\install.ps1 -Mode Apply -OptimizationProfiles standard,privacy,gaming
```

Avant une mutation réelle, l'orchestrateur tente de créer un point de restauration et capture des mesures avant/après.

V8 ajoute les réglages de réactivité Windows dans la même philosophie réversible.

Guides :

- [`docs/14_WINDOWS_OPTIMIZATION_V4.md`](docs/14_WINDOWS_OPTIMIZATION_V4.md) ;
- [`docs/20_WINDOWS_RESPONSIVENESS_V8.md`](docs/20_WINDOWS_RESPONSIVENESS_V8.md).

---

## Microsoft Defender

Defender reste actif.

Le projet suit une politique **deny-by-default** pour les exclusions :

```text
config/defender/exclusions.approved.json
```

est vide par défaut.

Une exclusion ne doit être ajoutée qu'après mesure d'un hotspot réel.

Guide : [`docs/05_DEFENDER_PERFORMANCE.md`](docs/05_DEFENDER_PERFORMANCE.md).

---

## Sauvegarde et reprise V7

La protection repose sur plusieurs niveaux :

```text
Point de restauration
        ↓
rollback léger Windows

WindowsImageBackup
        ↓
C: + D: + volumes critiques

Export WSL VHDX + SHA-256
        ↓
restauration Ubuntu indépendante

GitHub
        ↓
reconstruction du socle automatisé
```

La cible de Golden Backup doit être un **disque USB NTFS séparé**, avec au moins 100 Go libres selon la politique actuelle.

Création :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
```

Vérification :

```powershell
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
```

Plan de restauration :

```powershell
.\install.ps1 -BackupAction RestorePlan -BackupTargetDrive E:
```

Aucune restauration bare-metal destructive n'est lancée automatiquement.

Guide : [`docs/18_BACKUP_DISASTER_RECOVERY_V7.md`](docs/18_BACKUP_DISASTER_RECOVERY_V7.md).

---

## System Update Manager V11

Point d'entrée :

```powershell
.\update.ps1 -Mode Audit
.\update.ps1 -Mode Apply
.\update.ps1 -Mode Verify
```

V11 couvre :

- Windows Update ;
- applications WinGet ;
- runtime WSL ;
- Ubuntu/APT ;
- outils DevOps épinglés ;
- extensions VS Code.

Par défaut :

- les drivers Windows Update sont exclus ;
- les mises à jour facultatives Windows sont exclues ;
- les pins WinGet sont respectés ;
- aucun `dist-upgrade` Ubuntu ;
- aucun `autoremove` agressif ;
- aucun flash BIOS/firmware ;
- aucun redémarrage forcé.

Guide : [`docs/22_SYSTEM_UPDATE_MANAGER_V11.md`](docs/22_SYSTEM_UPDATE_MANAGER_V11.md).

---

## OpenClaw / OpenRouter

L'intégration OpenClaw est isolée sous :

```text
D:\AI\OpenClaw
```

Le dépôt Windows utilise un contrôle-plane versionné et ne supprime pas automatiquement les données ou identifiants lors d'un rollback global.

Guide : [`docs/19_OPENCLAW_OPENROUTER_WINDOWS.md`](docs/19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

## Installation depuis un Windows propre

Le tutoriel détaillé est :

[`docs/01_INSTALLATION_WINDOWS.md`](docs/01_INSTALLATION_WINDOWS.md)

Le Runbook de reconstruction complet est :

[`docs/13_RUNBOOK_REINSTALLATION.md`](docs/13_RUNBOOK_REINSTALLATION.md)

Après récupération du dépôt, la séquence la plus simple est :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\menu.ps1
```

Puis choisir **1 — Installation complète**.

Pour un opérateur qui préfère les commandes :

```powershell
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Apply -FullInstall
.\install.ps1 -Mode Verify -ValidateHardware -ValidateWsl -ValidateDevOps -ValidateOpenClawAI
```

Certaines validations matérielles exigent des preuves manuelles, car Windows ne peut pas prouver de façon fiable le réglage UEFI ReBAR/Above 4G, l'emplacement physique exact des SSD ou la stabilité mémoire.

---

## Journaux et rapports

Les exécutions V9 conservent notamment :

```text
logs/<script>.log
logs/runs/<RunId>/events.ndjson
logs/runs/<RunId>/summary.json
reports/
```

Le menu V12 permet d'ouvrir directement `logs\` et `reports\`.

Une réussite n'est pas déclarée uniquement parce qu'une commande s'est lancée : les composants cherchent une preuve machine exploitable puis revalident leur état.

---

## Sécurité : limites volontaires

Le dépôt ne doit jamais :

- formater automatiquement un SSD ;
- flasher automatiquement l'UEFI/BIOS ;
- activer un overclocking/PBO agressif ;
- forcer la DDR5 6000 si elle n'est pas stable ;
- désactiver Defender globalement ;
- ajouter des exclusions Defender non approuvées ;
- déplacer les projets Linux vers `/mnt/c` ou `/mnt/d` ;
- contourner les versions DevOps épinglées ;
- forcer un redémarrage sans décision utilisateur ;
- exécuter automatiquement une restauration bare-metal destructive.

---

## Documentation

Point d'entrée documentaire :

[`docs/README.md`](docs/README.md)

Guide maître consolidé :

[`docs/24_GUIDE_MAITRE_V13.md`](docs/24_GUIDE_MAITRE_V13.md)

Documents essentiels :

- [`docs/00_ARCHITECTURE.md`](docs/00_ARCHITECTURE.md) — architecture globale ;
- [`docs/01_INSTALLATION_WINDOWS.md`](docs/01_INSTALLATION_WINDOWS.md) — installation Windows 11 depuis zéro ;
- [`docs/02_BIOS_DRIVERS.md`](docs/02_BIOS_DRIVERS.md) — UEFI/BIOS et pilotes ;
- [`docs/13_RUNBOOK_REINSTALLATION.md`](docs/13_RUNBOOK_REINSTALLATION.md) — reconstruction opérationnelle ;
- [`docs/16_WSL2_GUIDE_COMPLET.md`](docs/16_WSL2_GUIDE_COMPLET.md) — WSL2 débutant à avancé ;
- [`docs/18_BACKUP_DISASTER_RECOVERY_V7.md`](docs/18_BACKUP_DISASTER_RECOVERY_V7.md) — sauvegarde/reprise ;
- [`docs/21_DEVOPS_TERMINAL_V10.md`](docs/21_DEVOPS_TERMINAL_V10.md) — terminal DevOps ;
- [`docs/22_SYSTEM_UPDATE_MANAGER_V11.md`](docs/22_SYSTEM_UPDATE_MANAGER_V11.md) — mises à jour ;
- [`docs/23_INTERACTIVE_CONTROL_CENTER_V12.md`](docs/23_INTERACTIVE_CONTROL_CENTER_V12.md) — menu V12.

---

## État du projet

| Version | État | Fonction |
|---|---|---|
| V1 | intégrée | architecture Windows/NTFS/WSL/Defender |
| V2 | intégrée | tuning Windows et stack DevOps |
| V3 | intégrée | workstation VS Code/WezTerm/OpenSSH |
| V4 | intégrée | optimisation Windows réversible |
| V5 | intégrée | qualification matérielle |
| V6 | intégrée | tuning WSL2 adapté au matériel |
| V7 | intégrée | sauvegarde et disaster recovery |
| V8 | intégrée | réactivité Windows |
| V9 | intégrée | orchestration machine-first/idempotence/logs |
| V10 | intégrée | terminal Bash DevOps WezTerm + VS Code |
| V11 | intégrée | gestionnaire global de mises à jour |
| V12 | intégrée | centre de contrôle interactif |
| V13 documentation | documentation | consolidation README/Runbook/guide maître |

La CI valide les contrats techniques ; la validation finale d'une installation complète reste une opération à exécuter sur la vraie machine Windows, car un runner GitHub ne peut pas reproduire le firmware, les SSD, le GPU, les pilotes et les redémarrages réels du PC.
