# Changelog

## V13 — Documentation consolidée

- refonte du `README.md` pour refléter l'état réel V12 du projet ;
- ajout de `docs/README.md` comme hub documentaire et parcours de lecture débutant ;
- refonte complète de `docs/01_INSTALLATION_WINDOWS.md`, depuis la préparation du média Windows jusqu'à la validation et au Golden Backup ;
- refonte de `docs/13_RUNBOOK_REINSTALLATION.md` en véritable procédure de reconstruction/disaster recovery ;
- ajout de `docs/24_GUIDE_MAITRE_V13.md`, documentation consolidée de l'architecture, des versions V1→V12 et de l'exploitation ;
- alignement des guides architecture, stockage, applications, backup et validation avec V7/V9/V10/V11/V12 ;
- suppression des références documentaires obsolètes au faux chemin `docs/12_RUNBOOK_REINSTALLATION.md` ;
- ajout de contrôles CI documentaires pour empêcher la réapparition de liens cassés et d'informations structurelles obsolètes.

## V12 — Interactive Control Center

- ajout de `menu.ps1` comme point d'entrée humain principal ;
- ajout de `START_MENU.cmd` pour lancement par double-clic ;
- routage vers installation complète, logiciels, mises à jour, sauvegarde, restauration/rollback, audit, vérification et composants spécifiques ;
- élévation UAC limitée aux actions qui en ont besoin ;
- mode `DryRun` pour prouver le routage sans mutation ;
- CI V12 dédiée et documentation `docs/23_INTERACTIVE_CONTROL_CENTER_V12.md`.

## V11 — System Update Manager

- ajout de `update.ps1` ;
- gestion coordonnée de Windows Update, WinGet, WSL, Ubuntu/APT, versions DevOps épinglées et extensions VS Code ;
- drivers et mises à jour Windows facultatives exclus par défaut ;
- pins WinGet respectés ;
- aucun `dist-upgrade`, `autoremove` agressif, flash BIOS/firmware ou reboot forcé ;
- rapport V11 et revalidation après mise à jour ;
- documentation `docs/22_SYSTEM_UPDATE_MANAGER_V11.md`.

## V10 — DevOps Terminal

- WezTerm devient le terminal Windows principal avec Ubuntu WSL/Bash par défaut et PowerShell 7 en secondaire ;
- VS Code utilise le même Bash WSL ;
- ajout de Starship, fzf, zoxide, eza, bat, fd, ripgrep et des alias/complétions DevOps ;
- ajout de JetBrainsMono Nerd Font ;
- gestion idempotente et rollbackable du profil Bash ;
- CI V10 prouvant le second Apply no-op et l'absence de duplication `.bashrc` ;
- documentation `docs/21_DEVOPS_TERMINAL_V10.md`.

## V9 — Orchestration, Logs & Idempotence

- `install.ps1` devient l'orchestrateur unique : découverte machine, plan factuel, confirmation, Apply ciblé, re-Verify et synthèse ;
- ajout du moteur commun `scripts/core/runtime.psm1` ;
- ajout d'un journal persistant dédié à chaque script sous `logs/<catégorie>/<script>.log` ;
- ajout d'un `RunId`, d'événements NDJSON et d'un `summary.json` par exécution ;
- ajout de `reports/orchestration/machine-state.json` et `latest-run.json` ;
- les fichiers `state/` restent réservés au rollback/historique et ne constituent jamais une source de vérité ;
- WinGet, WSL2, VS Code, WezTerm, OpenSSH, OneDrive, réglages Windows, profils V4 et exclusions Defender vérifient leur état avant mutation ;
- les composants déjà conformes sont signalés `DÉJÀ OK` et ne sont pas réappliqués ;
- les changements sont revalidés avant d'être déclarés `FAIT` ;
- ajout d'une préparation guidée de l'utilisateur WSL non-root avec mot de passe saisi directement par Linux et jamais journalisé ;
- les scripts Bash DevOps et validation DevOps disposent de journaux séparés ;
- ajout de `-PlanOnly`, `-NonInteractive`, `-Yes`, `-WslUser` et `-FullInstall` ;
- les contrôles physiques/BIOS impossibles à automatiser sont explicitement marqués `ACTION_REQUISE` et peuvent être saisis avec `51_hardware_manual_checks.ps1 -Mode Record -Interactive` ;
- masquage automatique des arguments sensibles dans les journaux ;
- documentation `docs/21_ORCHESTRATION_IDEMPOTENCE_V9.md` et `logs/README.md`.

## V8 — Windows Responsiveness

- ajout de `config/windows/v8/responsiveness.json` pour figer la politique de réactivité Windows ;
- Memory Compression, Application Launch Prefetching et Application PreLaunch attendus actifs ;
- pagefile géré par le système et Automatic Memory Dump (`CrashDumpEnabled=7`) ;
- plan Balanced conservé avec mode secteur Best Performance via l'API Windows 11 officielle ;
- animations réduire/restaurer et animations de zone cliente désactivées via `SystemParametersInfo` ;
- inventaire des applications de démarrage sans désactivation automatique ;
- TRIM et Scheduled Optimize conservés, alerte espace libre sous 15 % ;
- benchmark léger enrichi : commit mémoire, pagefile, MMAgent, file d'attente disque et plan d'alimentation ;
- aucun RAM cleaner, purge Standby List, tweak HPET/BCD, désactivation core parking/C-States, service massif ou benchmark SSD d'écriture ;
- intégration complète Audit / Apply / Verify / Rollback dans `install.ps1` ;
- workflow CI `Windows responsiveness V8` avec audit Windows réel et garde-fous anti-régression ;
- documentation `docs/20_WINDOWS_RESPONSIVENESS_V8.md`.

## V7 — Backup / Disaster Recovery / OpenClaw

- ajout d'un bootstrap optionnel OpenClaw + OpenRouter natif Windows ;
- séparation stricte entre `D:\WSL` pour les workloads Linux DevOps et `D:\AI\OpenClaw` pour la pile IA ;
- clone/mise à jour protégée du plan de contrôle privé `openclaw_openrouter` sous `D:\AI\OpenClaw\control-plane` ;
- installation et qualification depuis `install.ps1` avec `-InstallOpenClawAI` et `-ValidateOpenClawAI` ;
- aucun effacement automatique de l'état OpenClaw pendant un rollback ;
- ajout de la stratégie Backup & Disaster Recovery V7 : image Windows, export WSL2 VHDX, manifest et SHA-256 ;
- restauration V7 guidée, sans formatage, `wsl --unregister` ni `wbadmin start sysrecovery` automatique ;
- documentation dédiée `docs/18_BACKUP_DISASTER_RECOVERY_V7.md` et `docs/19_OPENCLAW_OPENROUTER_WINDOWS.md`.

## V6 — WSL2 matériel et accès distant

- profils WSL2 `standard`, `lab-heavy` et `nat-fallback` dimensionnés pour le Ryzen 7 7700 et 48 Go de RAM ;
- stockage Ubuntu sous `D:\WSL\Ubuntu-DevOps` avec projets Linux dans le filesystem ext4 WSL2 ;
- réseau mirrored, DNS tunneling, firewall WSL/Hyper-V, sparse VHD et autoMemoryReclaim ;
- PowerShell 7 dans le socle Windows ;
- VS Code Remote - WSL, Remote - SSH et SFTP/FTP ;
- validation runtime WSL2 V6 et contrat CI Ubuntu 26.04 / resolute.

## V5 — Hardware Qualification

- cible matérielle versionnée : Ryzen 7 7700, MSI B850M Mortar WiFi, 48 Go DDR5 6000, Arc B580 et 2× Crucial T705 ;
- inventaire matériel et checklist manuelle BIOS/ReBAR/M.2/refroidissement/stabilité mémoire ;
- politique `config/hardware/symbiosis-v5.json` avec baselines pilotes AMD/Intel et seuils thermiques T705 ;
- audit VBS/HVCI, réseau Realtek 8126/Wi-Fi et télémétrie NVMe sans mutation automatique ;
- interdiction des auto-tweaks PBO, Curve Optimizer, timings DDR5, OC/undervolt GPU, timers BCD, offloads réseau et flash BIOS/SSD ;
- audit de symbiose exécuté systématiquement dans le cycle `install.ps1` avant toute phase Apply/Verify ;
- qualification finale stricte avec `-ValidateHardware` et preuves manuelles.

## V4 — Windows Optimization

- profils `standard`, `privacy`, `gaming` et `optional` ;
- audit, apply, verify et rollback par profil ;
- benchmark avant/après et comparaison ;
- point de restauration avant modification sauf opt-out explicite ;
- garde-fous contre les tweaks destructifs ou non mesurés.

## V3 — Workstation DevOps

- socle Windows pour VS Code, WezTerm, PowerShell, OpenSSH Client et outils workstation ;
- validation Windows/DevOps consolidée ;
- séparation des responsabilités entre Windows et les outils Linux dans WSL2.

## V2

- tuning Windows réversible avec Audit / Apply / Verify / Rollback ;
- audit matériel, stockage, TRIM, mémoire, WSL et Defender ;
- Defender deny-by-default avec Performance Analyzer et rollback fiable ;
- WSL2 systemd + Docker Engine natif sans Docker Desktop ;
- kubectl, Helm, Minikube, kind, Terraform, AWS CLI v2, Ansible, GitHub CLI, Trivy, ShellCheck et shfmt ;
- rotation des logs Docker pour limiter la croissance du VHDX ;
- validation Bash, ShellCheck, PowerShell et JSON en CI ;
- runbook complet de réinstallation.

## V1

- architecture Windows 11 Pro + deux SSD NTFS ;
- WSL2 stocké sur `D:` sans partition EXT4 physique ;
- profils WSL2 standard / lab-heavy / NAT fallback ;
- bootstrap applications WinGet ;
- audit initial Defender ;
- documentation architecture, stockage, BIOS, applications, gaming et sauvegarde.
