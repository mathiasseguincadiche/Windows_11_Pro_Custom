# Validation — comment prouver que la workstation est réellement prête

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

Ce document présente les validations principales du `main` actuel, de V3 jusqu'aux couches V12.

---

## 1. Validation de base Windows / workstation

Commande :

```powershell
.\install.ps1 -Mode Verify
```

Elle vérifie notamment les composants inclus dans la portée normale de l'orchestrateur :

- applications automatiques ;
- réglages Windows de base ;
- profils V4 demandés ;
- réactivité V8 ;
- WSL2 ;
- utilisateur WSL ;
- workstation VS Code / WezTerm / OpenSSH ;
- exclusions Defender approuvées ;
- Defender actif ;
- qualification Windows V3.

Le validateur V3 contrôle notamment :

- Windows 11 ;
- `C:` en NTFS ;
- `D:` en NTFS ;
- Defender actif ;
- protection temps réel active ;
- absence d'exclusion racine dangereuse `C:\` / `D:\` ;
- WSL disponible ;
- profil WSL demandé ;
- distribution Ubuntu présente ;
- emplacement sous `D:\WSL\Ubuntu-DevOps` ;
- workstation VS Code/WezTerm conforme.

---

## 2. Validation matérielle V5

Commande :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

Elle combine :

### Faits automatiques

- CPU ;
- cœurs / threads ;
- quantité et fréquence RAM visible ;
- carte mère ;
- GPU / driver ;
- SSD / santé / filesystem ;
- GPT ;
- Secure Boot ;
- TPM ;
- virtualisation firmware ;
- affichage ;
- plan d'alimentation.

### Faits manuels obligatoires pour le verdict complet

- CSM désactivé ;
- Above 4G ;
- ReBAR ;
- emplacement physique des T705 ;
- refroidissement/airflow ;
- stabilité RAM 6000 ;
- revue BIOS stable ;
- revue drivers constructeur.

Saisie guidée :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Record -Interactive
```

Le projet refuse de fabriquer ces preuves à partir d'une supposition.

Verdict cible :

```text
VERDICT: V5 HARDWARE READY
```

---

## 3. Validation WSL2 V6

Commande :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

Le contrat courant exige :

```text
Ubuntu 26.04
D:\WSL\Ubuntu-DevOps
HOME ext4
ressources conformes au profil choisi
systemd / environnement attendu
racines de travail Linux conformes
```

Le profil de référence est contrôlé par rapport aux fichiers versionnés dans `config/wsl/`.

Verdict cible :

```text
VERDICT: V6 WSL2 PLATFORM READY
```

---

## 4. Validation DevOps

Commande :

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

Le validateur Linux contrôle notamment :

- Git ;
- Docker Engine ;
- Docker Compose ;
- Buildx selon le socle ;
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
- accès Docker attendu ;
- service Docker ;
- politique de logs Docker ;
- HOME hors de `/mnt/c` et `/mnt/d` ;
- racines Linux de travail ;
- profil shell ;
- tests/contrats DevOps associés.

Les versions critiques doivent correspondre à :

```text
config/devops/tool-versions.env
```

et non à une version `latest` arbitraire.

Verdict historique attendu :

```text
VERDICT: V3 DEVOPS READY
```

Le nom V3 est conservé pour compatibilité historique même si la stack est aujourd'hui utilisée dans l'architecture V12.

---

## 5. Validation Windows Optimization V4

Après un vrai `Apply`, les mesures avant/après doivent exister pour permettre la comparaison.

Rapports typiques :

```text
reports/windows/v4-benchmark-before.json
reports/windows/v4-benchmark-after.json
reports/windows/v4-benchmark-comparison.json
reports/validation-v4.json
```

Le `Verify` signale `ACTION_REQUISE` si les preuves nécessaires à la validation V4 n'existent pas encore.

Verdict cible :

```text
VERDICT: V4 WINDOWS OPTIMIZATION READY
```

---

## 6. Validation Backup V7

Une sauvegarde ne peut pas être validée par la CI seule : il faut une vraie cible physique et une vraie image.

Créer :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
```

Vérifier :

```powershell
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
```

Le validateur exige notamment :

- `WindowsImageBackup` ;
- version énumérable par `wbadmin` ;
- WinRE actif ;
- manifest V7 ;
- export VHDX Ubuntu ;
- SHA-256 valide ;
- politique destructive désactivée.

Verdict runtime cible :

```text
VERDICT: V7 BACKUP READY
```

---

## 7. Validation réactivité V8

La réactivité Windows est un composant géré et vérifiable, pas une suite de tweaks invisibles.

Elle est incluse dans le `Verify` normal de `install.ps1`.

Le rollback utilise l'état initial V8 uniquement s'il a réellement été enregistré.

---

## 8. Validation orchestration V9

V9 vérifie surtout le **processus de convergence** :

```text
facts machine
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

Une deuxième exécution conforme doit éviter une mutation inutile.

Journaux :

```text
logs/
logs/runs/<RunId>/events.ndjson
logs/runs/<RunId>/summary.json
```

---

## 9. Validation terminal V10

Le contrat terminal vérifie notamment :

- WezTerm configuré ;
- Ubuntu/Bash profil principal ;
- PowerShell 7 disponible ;
- VS Code terminal WSL ;
- profil Bash géré ;
- Starship / outils CLI prévus ;
- absence de duplication du bloc `.bashrc` ;
- Apply idempotent ;
- rollback du profil.

Le rendu physique de la Nerd Font reste à observer sur la vraie machine : une CI ne voit pas ton écran.

---

## 10. Validation mises à jour V11

```powershell
.\update.ps1 -Mode Verify
```

V11 recontrôle les catégories qu'il gère :

```text
Windows Update
WinGet
WSL
Ubuntu/APT
DevOps pinned
VS Code extensions
```

Un reboot requis n'est pas masqué : il est signalé comme action à effectuer.

---

## 11. Validation menu V12

La CI teste le routage du centre de contrôle en `DryRun` afin de vérifier qu'une option appelle le bon orchestrateur sans exécuter de mutation sur le runner.

Exemple :

```powershell
.\menu.ps1 -Choice 1 -DryRun -NoPause -NoClear
```

Sur la vraie machine, la validation fonctionnelle consiste également à confirmer :

- affichage correct ;
- choix lisibles ;
- UAC sur les actions nécessitant l'administration ;
- retour correct vers les orchestrateurs ;
- logs/rapports accessibles.

---

## 12. OpenClaw / OpenRouter

Si utilisé :

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

Validation étendue :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateOpenClawAI
```

Le control-plane doit correspondre au SHA épinglé dans le dépôt Windows.

La clé API OpenRouter n'est pas une preuve Git et ne doit pas être commitée.

---

## 13. Commande de validation complète recommandée

Après une installation/reconstruction complète :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateOpenClawAI
```

Puis :

```powershell
.\update.ps1 -Mode Verify
```

Et après création réelle du Golden Backup :

```powershell
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
```

---

## 14. CI GitHub

Le dépôt possède des workflows spécialisés qui couvrent notamment :

- parsing PowerShell ;
- PSScriptAnalyzer ;
- Bash / ShellCheck ;
- actionlint ;
- JSON / configurations structurées ;
- syntaxe WezTerm ;
- garde-fous contre les opérations destructives ;
- V5 hardware contracts ;
- WSL runtime ;
- backup safety ;
- orchestration/idempotence ;
- versions DevOps épinglées ;
- terminal V10 ;
- updates V11 ;
- menu V12.

Un workflow spécialisé peut ne pas se déclencher sur un commit documentaire à cause de ses filtres de chemins ; cela ne signifie pas que le workflow n'existe plus. La non-régression documentaire V13 doit compléter ces contrôles.

---

## 15. Ce que la CI ne peut pas prouver

La CI ne peut pas affirmer qu'une vraie machine possède :

- le BIOS voulu ;
- ReBAR réellement actif ;
- DDR5 stable à 6000 ;
- les T705 physiquement aux bons slots ;
- les températures correctes ;
- un vrai Golden Backup sur USB ;
- un rendu graphique correct de WezTerm ;
- un Windows Update réellement terminé après reboot.

Ces points nécessitent une validation runtime réelle.

---

## 16. Règle de sortie

Un composant est qualifié seulement si :

```text
son contrat est clair
+
sa preuve est disponible
+
son Verify passe
+
les ACTION_REQUISE pertinentes sont traitées
```

Un `KO` ou une preuve manquante ne doit pas être renommé en succès pour terminer plus vite.
