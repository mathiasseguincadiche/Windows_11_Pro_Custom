# Validation — prouver que la workstation est réellement prête

La validation du projet ne se résume pas à « le script n'a pas affiché d'erreur ».

Le principe est :

```text
état désiré
+
état réel
↓
contrôles explicites
↓
preuve exploitable
↓
verdict
```

Ce document décrit **les validations du `main` actuel**, sans demander au lecteur de connaître l'ordre historique dans lequel elles ont été ajoutées.

---

## Validation de base Windows / workstation

Commande :

```powershell
.\install.ps1 -Mode Verify
```

Elle vérifie notamment les composants inclus dans la portée normale de l'orchestrateur :

- applications gérées ;
- réglages Windows ;
- réactivité ;
- WSL2 ;
- utilisateur WSL ;
- VS Code / WezTerm / OpenSSH ;
- exclusions Defender approuvées ;
- Defender actif ;
- cohérence générale de la workstation.

La base Windows doit notamment confirmer :

- Windows 11 ;
- `C:` en NTFS ;
- `D:` en NTFS ;
- Defender actif ;
- protection temps réel active ;
- absence d'exclusion racine dangereuse `C:\` / `D:\` ;
- WSL disponible ;
- distribution Ubuntu présente ;
- stockage WSL attendu ;
- workstation VS Code/WezTerm cohérente.

---

## Validation matérielle

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

Elle combine :

### Faits automatiques

- CPU ;
- cœurs / threads ;
- RAM visible ;
- carte mère ;
- GPU / driver ;
- SSD / filesystems ;
- GPT ;
- Secure Boot ;
- TPM ;
- virtualisation firmware ;
- affichage ;
- plan d'alimentation ;
- autres informations observables sans mutation dangereuse.

### Faits manuels

- CSM ;
- Above 4G ;
- ReBAR ;
- emplacement physique des SSD ;
- refroidissement/airflow ;
- stabilité mémoire ;
- revue BIOS ;
- revue des pilotes constructeur.

Saisie guidée :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Record -Interactive
```

Le projet refuse de fabriquer ces preuves à partir d'une supposition.

Guide : [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

---

## Validation WSL2

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

Le contrat courant exige notamment :

```text
Ubuntu 26.04
D:\WSL\Ubuntu-DevOps
HOME ext4
ressources conformes au profil choisi
systemd actif
racines de travail Linux conformes
```

Le validateur compare l'état réel aux configurations courantes sous `config/wsl/`.

Guide : [`06_WSL2.md`](06_WSL2.md).

---

## Validation DevOps

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

Le validateur Linux contrôle notamment :

- Git ;
- Docker Engine ;
- Docker Compose ;
- Buildx ;
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
- TFLint ;
- service Docker ;
- politique de logs Docker ;
- HOME hors de `/mnt/c` et `/mnt/d` ;
- racines Linux ;
- profil shell ;
- smoke tests IaC.

Les versions critiques doivent correspondre à `config/devops/tool-versions.env` plutôt qu'à une version `latest` arbitraire.

Guide : [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md).

---

## Validation des optimisations Windows

Les réglages Windows gérés sont vérifiés après application.

Les mesures avant/après permettent d'éviter une validation basée uniquement sur le ressenti.

Les rapports vivent sous :

```text
reports/windows/
```

La validation doit également confirmer que les garde-fous restent intacts :

- Defender actif ;
- Windows Update disponible ;
- firewall actif ;
- WSL/Hyper-V fonctionnels ;
- pagefile et compression mémoire conservés selon la politique ;
- stockage et TRIM non cassés.

Guide : [`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md).

---

## Validation de la sauvegarde

Une sauvegarde ne peut pas être validée par la CI seule : il faut une vraie cible physique et de vrais artefacts.

Créer :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
```

Vérifier :

```powershell
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
```

Le validateur contrôle notamment :

- image Windows ;
- version récupérable ;
- WinRE ;
- manifest ;
- export VHDX Ubuntu ;
- SHA-256 ;
- absence de restauration destructive automatique.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

## Validation de l'orchestration

L'orchestration doit prouver le **processus de convergence** :

```text
faits machine
↓
Verify
↓
plan
↓
Apply delta seulement
↓
re-Verify
↓
logs / summary
```

Une deuxième exécution conforme doit éviter les mutations inutiles.

Journaux :

```text
logs/
logs/runs/<RunId>/events.ndjson
logs/runs/<RunId>/summary.json
```

Guide : [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md).

---

## Validation du terminal et de VS Code

Le contrat terminal vérifie notamment :

- WezTerm configuré ;
- Ubuntu/Bash comme environnement Linux principal ;
- PowerShell 7 disponible ;
- VS Code WSL ;
- profil Bash géré ;
- outils CLI prévus ;
- absence de duplication du bloc `.bashrc` ;
- comportement idempotent ;
- rollback du profil lorsque prévu.

Le rendu physique d'une police ou d'un écran ne peut pas être prouvé par une CI headless.

---

## Validation des mises à jour

```powershell
.\update.ps1 -Mode Verify
```

Le gestionnaire recontrôle les catégories qu'il gère :

```text
Windows Update
WinGet
WSL
Ubuntu/APT
DevOps épinglé
VS Code extensions
```

Un reboot requis n'est pas masqué : il reste une action à effectuer.

Guide : [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

## Validation du centre de contrôle

La CI teste le routage de `menu.ps1` en mode non destructif.

Exemple :

```powershell
.\menu.ps1 -Choice 1 -DryRun -NoPause -NoClear
```

Sur la vraie machine, il faut également confirmer :

- affichage correct ;
- choix lisibles ;
- élévation UAC uniquement lorsqu'elle est nécessaire ;
- routage correct vers les orchestrateurs ;
- accès aux logs/rapports.

Guide : [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md).

---

## OpenClaw / OpenRouter

Si l'intégration est utilisée :

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

Le contrôle doit notamment vérifier l'intégration attendue sans exposer de clé API dans Git ou dans les logs.

Guide : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

## Validation complète recommandée

Après une installation ou reconstruction :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

Si OpenClaw est utilisé :

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

Puis :

```powershell
.\update.ps1 -Mode Verify
```

Et après création d'une vraie sauvegarde :

```powershell
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
```

---

## Ce que la CI vérifie

Les workflows couvrent notamment :

- parsing PowerShell ;
- PSScriptAnalyzer ;
- Bash / ShellCheck ;
- actionlint ;
- JSON / configurations structurées ;
- WezTerm ;
- garde-fous destructifs ;
- contrats matériels ;
- runtime WSL ;
- sécurité backup ;
- orchestration/idempotence ;
- versions DevOps épinglées ;
- terminal ;
- mises à jour ;
- centre de contrôle ;
- cohérence documentaire.

---

## Ce que la CI ne peut pas prouver

La CI ne peut pas affirmer qu'une vraie machine possède :

- le BIOS voulu ;
- ReBAR réellement actif ;
- DDR5 réellement stable ;
- les SSD physiquement aux bons slots ;
- les températures correctes ;
- un vrai backup USB ;
- un rendu graphique parfait ;
- un Windows Update réellement finalisé après reboot.

Ces points nécessitent une validation runtime réelle.

---

## Règle de sortie

Un composant est qualifié seulement si :

```text
son contrat est clair
+
sa preuve est disponible
+
son Verify passe
+
les actions humaines pertinentes sont traitées
```

Un `KO` ou une preuve manquante ne doit jamais être renommé en succès simplement pour terminer plus vite.
