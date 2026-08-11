# Runbook — réinstallation complète

Ce runbook décrit l'ordre de reconstruction du poste à partir d'un Windows 11 Pro propre.

## Phase 0 — BIOS / UEFI

Contrôler avant installation :

- UEFI actif ;
- CSM désactivé ;
- fTPM / TPM actif ;
- Secure Boot prévu ;
- SVM actif pour la virtualisation ;
- Above 4G Decoding actif ;
- Resizable BAR actif pour l'Intel Arc B580 ;
- profil mémoire 6000 MT/s uniquement après validation de stabilité.

## Phase 1 — stockage

Architecture obligatoire :

```text
Crucial T705 #1 -> C: NTFS -> Windows 11 Pro
Crucial T705 #2 -> D: NTFS -> DATA / WSL / ISO / BACKUPS / EXPORTS
```

Aucune partition EXT4 physique.

Le dépôt ne contient aucune commande de formatage automatique.

## Phase 2 — Windows propre

1. Installer Windows 11 Pro sur le premier SSD.
2. Terminer Windows Update.
3. Installer les pilotes AMD chipset.
4. Installer le pilote Intel Arc.
5. Installer réseau / Wi-Fi / Bluetooth / audio nécessaires.
6. Vérifier le Gestionnaire de périphériques.
7. Initialiser le deuxième SSD en GPT + NTFS si nécessaire.
8. Attribuer la lettre `D:` au volume DATA.

## Phase 3 — dépôt

Depuis PowerShell administrateur :

```powershell
git clone https://github.com/mathiasseguincadiche/Windows_11_Pro_Custom.git
cd Windows_11_Pro_Custom
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Mode Audit
```

Ne pas lancer `Apply` si C: ou D: ne sont pas détectés en NTFS.

## Phase 4 — configuration Windows

```powershell
.\install.ps1 -Mode Apply
```

Ce passage :

- installe les applications WinGet validées ;
- applique les tweaks Windows réversibles ;
- sauvegarde l'état initial dans `state/` ;
- installe/configure WSL2 ;
- conserve Defender actif ;
- n'ajoute aucune exclusion Defender avec le manifeste livré par défaut.

Un redémarrage Windows peut être requis par WSL ou Windows Update. Après redémarrage, relancer la commande si l'étape WSL a été interrompue.

## Phase 5 — premier démarrage Ubuntu

Lancer la distribution Ubuntu une première fois et créer l'utilisateur Linux.

Les projets DevOps doivent ensuite vivre dans :

```text
/home/<user>/projects
```

Pas dans `/mnt/c` ou `/mnt/d`.

## Phase 6 — stack DevOps

Depuis PowerShell administrateur :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

Le bootstrap applique `/etc/wsl.conf`, active systemd puis installe la stack Linux.

À la fin :

```powershell
wsl --shutdown
```

Relancer ensuite Ubuntu pour que l'appartenance au groupe `docker` soit effective.

## Phase 7 — qualification

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

Puis, dans Ubuntu si nécessaire :

```bash
docker info
docker run --rm hello-world
minikube start --driver=docker
kubectl get nodes
helm version
terraform version
aws --version
ansible --version
```

## Phase 8 — Defender / I/O

Ne créer aucune exclusion au jugé.

Pour mesurer un workload lourd :

```powershell
.\scripts\defender\01_record.ps1 -Seconds 60
.\scripts\defender\02_report.ps1
```

Si un hotspot précis est démontré, documenter le chemin puis seulement ensuite modifier `config/defender/exclusions.approved.json`.

## Phase 9 — sauvegarde WSL

Après qualification de l'environnement :

```powershell
wsl --shutdown
wsl --export Ubuntu D:\BACKUPS\Ubuntu-DevOps.tar
```

Conserver les dépôts Git synchronisés avec leurs remotes ; l'export WSL ne remplace pas Git.

## Rollback des réglages Windows

```powershell
.\install.ps1 -Mode Rollback
```

Le rollback concerne les tweaks Registry et les exclusions Defender gérées par le dépôt. Il ne désinstalle pas les applications, WSL2 ou les outils Linux.

## Critère final

La machine est considérée prête lorsque :

```text
Windows validation : OK
C: NTFS            : OK
D: NTFS            : OK
Defender actif     : OK
WSL2               : OK
Docker Engine      : OK
Stack DevOps       : READY
```
