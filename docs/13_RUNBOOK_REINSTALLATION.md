# Runbook — réinstallation et reconstruction complète de la workstation

Ce Runbook sert après une panne, un remplacement de disque, une réinstallation volontaire ou une perte importante de configuration.

> **Frontière de sécurité :** ce dépôt peut préparer, auditer, converger et vérifier la workstation, mais il ne formate jamais automatiquement les SSD et ne déclenche jamais une restauration bare-metal destructive sans décision humaine.

## 1. Qualifier l'incident

Avant toute action destructive, vérifier Windows, `C:`, `D:`, WSL2, le VHDX Ubuntu, l'image Windows, l'export WSL et le support de sauvegarde externe.

Si Windows démarre encore :

```powershell
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Si le plan est cohérent :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

## 2. Protéger les données récupérables

Priorités : données personnelles, projets non poussés, clés SSH, configurations locales, secrets/credentials et VHDX WSL ou export disponible.

Les données appartenant à des projets externes doivent être restaurées selon les procédures de ces projets ; ce dépôt ne possède pas leur reconstruction applicative.

## 3. Vérifier le matériel

Avant de réinstaller, vérifier SSD, RAM, refroidissement, stabilité BIOS et alimentation. La qualification détaillée est dans [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

## 4. Réinstaller Windows

Utiliser une image Windows 11 officielle, démarrer en UEFI et installer Windows 11 Pro uniquement sur le SSD système prévu.

Après le premier démarrage : Windows Update, chipset AMD, pilote Intel Arc, pilotes MSI nécessaires, puis contrôle du Gestionnaire de périphériques.

## 5. Reconstruire `D:` si nécessaire

```text
D:\
├── DATA\
├── WSL\
│   ├── Ubuntu-DevOps\
│   └── swap\
├── ISO\
└── EXPORTS\
```

Les dossiers de projets externes ne font pas partie du contrat de reconstruction de ce dépôt.

## 6. Récupérer le dépôt

```powershell
mkdir C:\Dev -ErrorAction SilentlyContinue
cd C:\Dev
git clone https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom.git
cd Windows_11_Pro_Custom
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Mode Audit
```

## 7. Prévisualiser puis converger

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
.\install.ps1 -Mode Apply -FullInstall
```

`FullInstall` reconstruit uniquement la workstation Windows/WSL2/DevOps et ses qualifications. Il ne déclenche aucun projet externe.

## 8. WSL2 / Ubuntu

Contrat :

```text
Ubuntu 26.04
D:\WSL\Ubuntu-DevOps
HOME ext4
```

Après une modification de `.wslconfig` :

```powershell
wsl --shutdown
wsl -d Ubuntu
```

## 9. Restaurer un WSL sauvegardé

Importer d'abord le VHDX sous un nom distinct, par exemple `Ubuntu-Restore`, puis vérifier utilisateur, projets, permissions, Docker, outils DevOps et données avant toute décision sur l'ancienne distribution.

## 10. Stack DevOps

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
wsl --shutdown
.\install.ps1 -Mode Verify -ValidateWsl -ValidateDevOps
```

## 11. VS Code et WezTerm

Vérifier :

```text
Ubuntu DevOps (WSL2) -> environnement Linux principal
PowerShell 7         -> administration Windows
VS Code WSL          -> projets sous /home/<user>/...
```

Aucun profil ou bootstrap OpenClaw/`clawops` n'est géré ici.

## 12. Projets externes

OpenClaw/OpenRouter, s'il est utilisé sur la même machine, doit être réinstallé ou restauré **uniquement depuis `mathiasseguincadiche/openclaw_openrouter`**.

`Windows_11_Pro_Custom` ne possède aucun `ValidateOpenClawAI`, aucun control-plane pin et aucune procédure de restauration fonctionnelle de cette plateforme.

Voir [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

## 13. Validation globale

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

## 14. Maintenance et nouvelle sauvegarde

```powershell
.\update.ps1 -Mode Audit
.\update.ps1 -Mode Apply
.\update.ps1 -Mode Verify
```

Puis, une fois la workstation stable :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
.\install.ps1 -BackupAction RestorePlan -BackupTargetDrive E:
```

Guides : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md), [`11_VALIDATION.md`](11_VALIDATION.md), [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).
