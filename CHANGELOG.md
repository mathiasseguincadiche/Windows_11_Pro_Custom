# Changelog

Le `CHANGELOG.md` conserve **l'historique technique** du dépôt. Les numéros V1 à V13
ci-dessous décrivent les étapes de construction passées ; ils ne définissent plus
la documentation active ni l'identité actuelle de la workstation.

Pour l'état actuel du projet, utiliser :

- [`README.md`](README.md) — vision et usages de la workstation ;
- [`docs/README.md`](docs/README.md) — portail documentaire ;
- [`docs/18_GUIDE_MAITRE.md`](docs/18_GUIDE_MAITRE.md) — référence consolidée actuelle.

## Documentation canonique actuelle

- restauration d'un `README.md` centré sur la workstation elle-même : Windows 11
  Pro + WSL2 DevOps + desktop/gaming + maintenance + reprise après incident ;
- séparation claire entre **ce qu'est le projet** et les procédures permettant de
  l'installer ;
- consolidation de la documentation active dans une série canonique `00` à `26`,
  sans suffixes de versions historiques dans les noms des guides ;
- fusion des informations utiles des anciens guides V3 à V13 dans les documents
  canoniques actuels ;
- correction du guide WSL2 pédagogique pour refléter le contrat réellement
  utilisé : profil standard 20 Go / 8 threads / 8 Go de swap et profil lab-heavy
  28 Go / 12 threads / 12 Go de swap ;
- remplacement du workflow documentaire V13 par un contrat documentaire courant
  qui vérifie README, guides canoniques, liens locaux et cohérence WSL2 ;
- les noms techniques historiques encore présents dans `config/`, `scripts/`, les
  rapports ou certains identifiants internes restent inchangés lorsqu'ils font
  partie d'un contrat d'implémentation éprouvé ; leur historique est décrit ici,
  pas exposé comme structure documentaire principale.

---

## Historique des évolutions

### V26 — Preuves, dérive et restaurabilité renforcées

- distinction exécutable entre preuves `SIMULATED` et `PHYSICAL` : un runner CI ne peut plus produire une preuve physique ;
- ajout du commit Git, d'un diff champ par champ et d'un remplacement de baseline justifié avec archivage de l'état précédent ;
- liaison des nouvelles sessions Golden Backup à leur identifiant `wbadmin` exact, tout en gardant la compatibilité avec les anciens manifests ;
- contrôle anticipé de la capacité du scratch avant le drill WSL isolé ;
- correction du contrat `Invoke-WpcExternalCommand -AllowFailure` et ajout de tests runtime ;
- intégration des preuves et drills V26 dans le centre de contrôle ;
- sidecar SHA-256 atomique pour les nouvelles baselines V26, avec détection de corruption et migration explicite des baselines antérieures ;
- confirmation PHYSICAL désormais obligatoire séparément de l'attestation d'état sain ;
- nettoyage du drill WSL rendu fail-closed : la copie VHDX est conservée si le désenregistrement temporaire échoue ;
- code de sortie du point de restauration Golden Backup contrôlé et inscrit dans le manifeste ;
- validation globale du menu étendue au matériel, à WSL et à la stack DevOps ;
- vérification PGP d'AWS CLI conservée lors des mises à jour ;
- références GitHub Actions épinglées sur des commits immuables ;
- compteurs historiques d'erreurs NVMe rendus consultatifs, sans affaiblir le blocage sur les erreurs non corrigées.

### V25 — Identité physique du stockage et garde-fou WSL

- ajout d'une baseline locale, explicitement approuvée, pour les identités stables de `C:` et `D:` ;
- vérification du numéro de série et de l'UniqueId du disque, des identités de partition et du VolumeUniqueId ;
- blocage fail-closed si une lettre pointe vers un autre disque/volume, si un rôle disparaît ou si `D:` devient boot/système/masqué ;
- exigence de deux disques physiques distincts pour les rôles Windows et données/WSL ;
- appel du gate V25 avant V24, avant les fondations Windows et directement depuis le script WSL ;
- aucun enrôlement ou remplacement silencieux de la baseline ;
- rapport topologique complet et runbook de diagnostic sans écriture.

### V13 — Documentation consolidée

- refonte du `README.md` pour refléter l'état réel V12 du projet ;
- ajout de `docs/README.md` comme hub documentaire et parcours de lecture débutant ;
- refonte complète de `docs/01_INSTALLATION_WINDOWS.md`, depuis la préparation du média Windows jusqu'à la validation et au Golden Backup ;
- refonte de `docs/13_RUNBOOK_REINSTALLATION.md` en véritable procédure de reconstruction/disaster recovery ;
- ajout de l'ancien guide maître V13, depuis consolidé dans `docs/18_GUIDE_MAITRE.md` ;
- alignement des guides architecture, stockage, applications, backup et validation avec les couches techniques alors en vigueur ;
- suppression des références documentaires obsolètes au faux chemin `docs/12_RUNBOOK_REINSTALLATION.md` ;
- ajout de contrôles CI documentaires pour empêcher la réapparition de liens cassés et d'informations structurelles obsolètes.

### V12 — Interactive Control Center

- ajout de `menu.ps1` comme point d'entrée humain principal ;
- ajout de `START_MENU.cmd` pour lancement par double-clic ;
- routage vers installation complète, logiciels, mises à jour, sauvegarde, restauration/rollback, audit, vérification et composants spécifiques ;
- élévation UAC limitée aux actions qui en ont besoin ;
- mode `DryRun` pour prouver le routage sans mutation ;
- CI dédiée et documentation du Control Center, désormais consolidée dans `docs/17_CONTROL_CENTER.md`.

### V11 — System Update Manager

- ajout de `update.ps1` ;
- gestion coordonnée de Windows Update, WinGet, WSL, Ubuntu/APT, versions DevOps épinglées et extensions VS Code ;
- drivers et mises à jour Windows facultatives exclus par défaut ;
- pins WinGet respectés ;
- aucun `dist-upgrade`, `autoremove` agressif, flash BIOS/firmware ou reboot forcé ;
- rapport et revalidation après mise à jour ;
- documentation désormais consolidée dans `docs/15_MISES_A_JOUR.md`.

### V10 — DevOps Terminal

- WezTerm devient le terminal Windows principal avec Ubuntu WSL/Bash par défaut et PowerShell 7 en secondaire ;
- VS Code utilise le même Bash WSL ;
- ajout de Starship, fzf, zoxide, eza, bat, fd, ripgrep et des alias/complétions DevOps ;
- ajout de JetBrainsMono Nerd Font ;
- gestion idempotente et rollbackable du profil Bash ;
- CI prouvant le second Apply no-op et l'absence de duplication `.bashrc` ;
- documentation désormais consolidée dans `docs/07_DEVOPS_STACK.md`.

### V9 — Orchestration, Logs & Idempotence

- `install.ps1` devient l'orchestrateur unique : découverte machine, plan factuel, confirmation, Apply ciblé, re-Verify et synthèse ;
- ajout du moteur commun `scripts/core/runtime.psm1` ;
- ajout d'un journal persistant dédié à chaque script sous `logs/<catégorie>/<script>.log` ;
- ajout d'un `RunId`, d'événements NDJSON et d'un `summary.json` par exécution ;
- ajout de `reports/orchestration/machine-state.json` et `latest-run.json` ;
- les fichiers `state/` restent réservés au rollback/historique et ne constituent jamais une source de vérité ;
- WinGet, WSL2, VS Code, WezTerm, OpenSSH, OneDrive, réglages Windows, profils d'optimisation et exclusions Defender vérifient leur état avant mutation ;
- les composants déjà conformes sont signalés `DÉJÀ OK` et ne sont pas réappliqués ;
- les changements sont revalidés avant d'être déclarés `FAIT` ;
- ajout d'une préparation guidée de l'utilisateur WSL non-root avec mot de passe saisi directement par Linux et jamais journalisé ;
- les scripts Bash DevOps et validation DevOps disposent de journaux séparés ;
- ajout de `-PlanOnly`, `-NonInteractive`, `-Yes`, `-WslUser` et `-FullInstall` ;
- les contrôles physiques/BIOS impossibles à automatiser sont explicitement marqués `ACTION_REQUISE` ;
- masquage automatique des arguments sensibles dans les journaux ;
- documentation désormais consolidée dans `docs/14_ORCHESTRATION.md` et `logs/README.md`.

### V8 — Windows Responsiveness

- ajout d'une politique de réactivité Windows versionnée ;
- Memory Compression, Application Launch Prefetching et Application PreLaunch attendus actifs ;
- pagefile géré par le système et Automatic Memory Dump ;
- plan Balanced conservé avec mode secteur Best Performance ;
- animations ciblées ajustées de manière réversible ;
- inventaire des applications de démarrage sans désactivation automatique ;
- TRIM et Scheduled Optimize conservés, alerte espace libre sous 15 % ;
- benchmark léger enrichi ;
- aucun RAM cleaner, purge Standby List, tweak HPET/BCD, désactivation core parking/C-States, service massif ou benchmark SSD d'écriture ;
- intégration complète Audit / Apply / Verify / Rollback dans `install.ps1`.

### V7 — Backup / Disaster Recovery / OpenClaw

- ajout d'un bootstrap optionnel OpenClaw + OpenRouter natif Windows ;
- séparation stricte entre `D:\WSL` pour les workloads Linux DevOps et `D:\AI\OpenClaw` pour la pile IA ;
- clone/mise à jour protégée du plan de contrôle `openclaw_openrouter` sous `D:\AI\OpenClaw\control-plane` ;
- installation et qualification depuis `install.ps1` avec `-InstallOpenClawAI` et `-ValidateOpenClawAI` ;
- aucun effacement automatique de l'état OpenClaw pendant un rollback ;
- ajout de la stratégie de sauvegarde : image Windows, export WSL2 VHDX, manifest et SHA-256 ;
- restauration guidée, sans formatage, `wsl --unregister` ni restauration bare-metal automatique ;
- documentation actuelle : `docs/10_BACKUP_RESTORE.md` et `docs/19_OPENCLAW_OPENROUTER_WINDOWS.md`.

### V6 — WSL2 matériel et accès distant

- profils WSL2 `standard`, `lab-heavy` et `nat-fallback` dimensionnés pour le Ryzen 7 7700 et 48 Go de RAM ;
- stockage Ubuntu sous `D:\WSL\Ubuntu-DevOps` avec projets Linux dans le filesystem ext4 WSL2 ;
- réseau mirrored, DNS tunneling, firewall WSL/Hyper-V, sparse VHD et autoMemoryReclaim ;
- PowerShell 7 dans le socle Windows ;
- VS Code Remote - WSL, Remote - SSH et SFTP/FTP ;
- contrat CI Ubuntu 26.04 / resolute.

### V5 — Hardware Qualification

- cible matérielle versionnée : Ryzen 7 7700, MSI B850M Mortar WiFi, 48 Go DDR5 6000, Arc B580 et 2× Crucial T705 ;
- inventaire matériel et checklist manuelle BIOS/ReBAR/M.2/refroidissement/stabilité mémoire ;
- politique de symbiose matérielle avec baselines pilotes AMD/Intel et seuils thermiques T705 ;
- audit VBS/HVCI, réseau et télémétrie NVMe sans mutation automatique ;
- interdiction des auto-tweaks PBO, Curve Optimizer, timings DDR5, OC/undervolt GPU, timers BCD, offloads réseau et flash BIOS/SSD ;
- qualification finale stricte avec preuves manuelles.

### V4 — Windows Optimization

- profils `standard`, `privacy`, `gaming` et `optional` ;
- audit, apply, verify et rollback par profil ;
- benchmark avant/après et comparaison ;
- point de restauration avant modification sauf opt-out explicite ;
- garde-fous contre les tweaks destructifs ou non mesurés.

### V3 — Workstation DevOps

- socle Windows pour VS Code, WezTerm, PowerShell, OpenSSH Client et outils workstation ;
- validation Windows/DevOps consolidée ;
- séparation des responsabilités entre Windows et les outils Linux dans WSL2.

### V2

- tuning Windows réversible avec Audit / Apply / Verify / Rollback ;
- audit matériel, stockage, TRIM, mémoire, WSL et Defender ;
- Defender deny-by-default avec Performance Analyzer et rollback fiable ;
- WSL2 systemd + Docker Engine natif sans Docker Desktop ;
- kubectl, Helm, Minikube, kind, Terraform, AWS CLI v2, Ansible, GitHub CLI, Trivy, ShellCheck et shfmt ;
- rotation des logs Docker pour limiter la croissance du VHDX ;
- validation Bash, ShellCheck, PowerShell et JSON en CI ;
- runbook complet de réinstallation.

### V1

- architecture Windows 11 Pro + deux SSD NTFS ;
- WSL2 stocké sur `D:` sans partition EXT4 physique ;
- profils WSL2 standard / lab-heavy / NAT fallback ;
- bootstrap applications WinGet ;
- audit initial Defender ;
- documentation architecture, stockage, BIOS, applications, gaming et sauvegarde.
