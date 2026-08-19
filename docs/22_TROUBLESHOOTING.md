# Troubleshooting — diagnostiquer par domaine

Ce guide décrit comment diagnostiquer un écart sans mélanger les responsabilités.

Avant toute correction, identifier la source de vérité avec [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

Le principe général est :

```text
observer
→ identifier le domaine propriétaire
→ lire les preuves
→ comparer au contrat
→ appliquer uniquement le delta compris
→ revalider
```

---

# 1. Orchestration

## Symptôme : `Audit` fonctionne mais `Verify` échoue

C'est possible et normal :

```text
Audit  -> observe et décrit
Verify -> exige la conformité
```

### Diagnostic

1. repérer le composant en échec ;
2. lire le log du script correspondant ;
3. identifier le contrat attendu ;
4. décider si un `Apply` ciblé est nécessaire.

### Correction

```powershell
.\install.ps1 -Mode Apply -PlanOnly
```

Puis, si le plan est cohérent :

```powershell
.\install.ps1 -Mode Apply
```

Rejouer ensuite `Verify`.

---

## Symptôme : le même composant revient toujours dans le plan

### Cause probable

`Apply` et `Verify` ne parlent pas exactement du même état, ou une action externe modifie la configuration après convergence.

### Diagnostic

Comparer :

```text
ce que Verify teste
ce que Apply écrit
ce que la machine possède après Apply
```

Ne contourne pas le validateur. Corrige la divergence.

---

# 2. WSL2

## Symptôme : Ubuntu existe mais n'est pas reconnue conforme

Vérifier :

```powershell
wsl --list --verbose
wsl --status
wsl --version
```

Puis :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

Le contrat attend notamment :

```text
Ubuntu
WSL2
Ubuntu 26.04 / resolute
E:\WSL\Ubuntu-DevOps
```

Une distribution qui démarre mais se trouve au mauvais emplacement reste un écart réel.

Guide : [`06_WSL2.md`](06_WSL2.md).

---

## Symptôme : `.wslconfig` semble ignoré

Après modification :

```powershell
wsl --shutdown
```

Puis redémarrer Ubuntu.

Dans Ubuntu :

```bash
nproc
free -h
swapon --show
```

Comparer au profil réellement demandé.

---

## Symptôme : WSL mirrored networking pose problème

Commencer par qualifier le problème réseau réel avant de modifier le contrat.

Le dépôt possède un profil `nat-fallback` pour les cas nécessitant ce mode.

Ne passe pas toute la documentation en NAT uniquement parce qu'un réseau ponctuel fonctionne mal.

---

# 3. Stack DevOps

## Symptôme : Docker fonctionne, mais `ValidateDevOps` échoue

La qualification DevOps ne couvre pas uniquement Docker.

Elle peut échouer sur :

- Compose / Buildx ;
- kubectl ;
- Helm ;
- Minikube ;
- kind ;
- Terraform ;
- Ansible ;
- AWS CLI ;
- GitHub CLI ;
- Trivy ;
- versions épinglées.

### Diagnostic

Lire le validateur et :

```text
config/devops/tool-versions.env
```

### Correction

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

Puis :

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

Guide : [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md).

---

## Symptôme : une version Internet plus récente existe

Ce n'est pas automatiquement un bug.

Si le projet épingle une version dans :

```text
config/devops/tool-versions.env
```

cette version reste la cible jusqu'à décision explicite de mise à jour du contrat.

---

# 4. Windows Terminal / expérience terminal

## Symptôme : Windows Terminal n'ouvre pas PowerShell 7 - DevOps par défaut

La source de vérité est :

```text
config/windows-terminal/
```

Le profil par défaut attendu est :

```text
PowerShell 7 - DevOps
```

Diagnostic ciblé :

```powershell
.\scripts\windows\31_windows_terminal.ps1 -Mode Audit
```

Validation :

```powershell
.\scripts\windows\31_windows_terminal.ps1 -Mode Verify
```

Si le fragment, le fichier d'actions importé, le bloc PowerShell ou `settings.json` ne respectent pas le contrat, le composant signale précisément l'écart.

### Correction

```powershell
.\scripts\windows\31_windows_terminal.ps1 -Mode Apply
```

Le composant sauvegarde l'état initial qu'il possède avant la première mutation afin de permettre un rollback contrôlé.

---

## Symptôme : les profils sont absents ou dupliqués

Contrat géré :

```text
PowerShell 7 - DevOps
Ubuntu - DevOps
```

Les profils dynamiques `Windows.Terminal.PowershellCore` et `Windows.Terminal.Wsl` sont volontairement désactivés par le contrat afin d'éviter les doublons avec les profils versionnés.

Vérifier également que Windows Terminal a bien chargé le fragment :

```text
%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\Windows11ProCustom\terminal-devops.profiles.json
```

---

## Symptôme : `Ubuntu - DevOps` ne démarre pas

Le profil Windows Terminal ne provisionne pas WSL. Vérifier d'abord :

```powershell
wsl --list --verbose
```

La distribution attendue doit s'appeler :

```text
Ubuntu
```

Puis vérifier la couche WSL avec :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

Le shell Bash/Starship d'Ubuntu reste géré par les scripts WSL existants ; ne le duplique pas dans le composant Windows Terminal.

---

## Symptôme : Starship ou les icônes sont absents sous PowerShell

Vérifier :

```powershell
Get-Command starship
.\scripts\windows\31_windows_terminal.ps1 -Mode Verify
```

Le contrat attend également `JetBrainsMono Nerd Font`. Windows Terminal et Starship sont installés par le bootstrap applicatif, pas téléchargés par le script de configuration terminal.

---

# 5. VS Code / remote

## Symptôme : VS Code travaille sur le mauvais filesystem

Pour un projet Linux, vérifier que la fenêtre VS Code est réellement connectée à WSL.

Le chemin de projet doit ressembler à :

```text
/home/<user>/projects/...
```

et non :

```text
/mnt/c/...
/mnt/e/...
```

`/mnt/c` et `/mnt/e` restent accessibles pour des échanges ponctuels avec Windows, mais sont **interdits comme racines de projets ou de workspaces DevOps**. Si VS Code ouvre un projet Linux depuis l'un de ces montages, déplace ou reclone le projet sous le filesystem ext4 WSL2.

---

# 6. OpenClaw / OpenRouter

Ce domaine est **hors périmètre** de `Windows_11_Pro_Custom`.

Le dépôt Windows ne possède ni l'installation, ni la configuration, ni la maintenance, ni la validation d'OpenClaw/OpenRouter.

Pour tout problème concernant :

- OpenClaw ;
- OpenRouter ;
- `clawops` ;
- Gateway ;
- modèles ;
- agents ;
- runtime lock ;
- credentials IA ;

utiliser exclusivement le dépôt `mathiasseguincadiche/openclaw_openrouter` et sa documentation.

La présence d'un problème dans ce projet externe ne doit pas faire échouer la conformité de la workstation.

Frontière : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

# 7. Matériel

## Symptôme : la qualification matérielle demande une action humaine

C'est normal lorsque l'information ne peut pas être déterminée honnêtement depuis Windows.

Exemples :

- emplacement physique d'un SSD ;
- stabilité RAM ;
- réglage UEFI précis ;
- refroidissement.

Commande de saisie guidée :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Record -Interactive
```

Puis :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

Le projet préfère `ACTION REQUISE` à une preuve inventée.

---

# 8. Stockage

## Symptôme : `E:` n'est pas conforme

Vérifier :

```powershell
Get-Volume -DriveLetter E
```

Puis :

```powershell
Get-Disk
```

Points importants :

```text
E: existe
NTFS
espace disponible
bon SSD physique
```

Ne formate pas automatiquement le volume parce que la lettre ou le filesystem ne correspond pas à une attente. Commence par identifier ce que contient réellement le disque.

---

# 9. Maintenance

## Symptôme : `update.ps1` demande une action humaine

Commencer par :

```powershell
.\update.ps1 -Mode Audit
```

Puis lire :

```text
reports\updates\latest-run.json
```

Les causes possibles incluent :

- redémarrage Windows ;
- version majeure Ubuntu ;
- incohérence d'un package épinglé ;
- réseau indisponible ;
- driver nécessitant une décision.

Ne force pas automatiquement un reboot ou une mise à niveau majeure simplement pour obtenir un état vert.

---

# 10. Sauvegarde

## Symptôme : la sauvegarde existe mais n'est pas acceptée comme valide

Une présence de dossier n'est pas une validation.

Vérifier :

- image Windows ;
- manifest ;
- export WSL ;
- hash ;
- espace / cible ;
- cohérence avec la politique actuelle.

Commande :

```powershell
.\install.ps1 -BackupAction Verify -BackupTargetDrive F:
```

Utilise la lettre réelle de ton support externe.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

# 11. Documentation / CI

## Symptôme : le workflow `Documentation` échoue

Causes fréquentes :

- document canonique absent ;
- ancien guide versionné réapparu ;
- lien Markdown local cassé ;
- contrat WSL2 différent entre plusieurs guides ;
- paramètres publics absents de la référence ;
- frontière OpenClaw/OpenRouter contredite par la documentation active.

La correction doit rendre la documentation fidèle au code et au contrat actuels.

---

# 12. Logs et rapports

En cas d'échec d'un run :

```text
logs\install.log
logs\runs\<RunId>\events.ndjson
logs\runs\<RunId>\summary.json
```

Puis chercher le log du composant concerné.

Un ancien log peut expliquer un incident passé, mais ne prouve pas la conformité présente.

---

# 13. Reconstruction

## Symptôme : plusieurs composants sont cassés et la machine semble incohérente

Ne saute pas immédiatement à une réinstallation complète.

Commence par :

```powershell
.\install.ps1 -Mode Audit
```

Avant le plan strict, confirmer d'abord que l'identité physique du stockage est
toujours conforme :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Verify
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Si V25 échoue, ne pas remplacer la baseline pour contourner l'alerte ; suivre
[`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md).

Si le stockage, Windows ou WSL sont réellement endommagés, utiliser :

[`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md).

Le Runbook opérationnel quotidien reste :

[`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).

---

## Résumé rapide

| Domaine | Première référence |
| --- | --- |
| orchestration | `install.ps1` + logs |
| WSL2 | `06_WSL2.md` |
| DevOps | `07_DEVOPS_STACK.md` |
| terminal | `config/windows-terminal/` + `scripts/windows/31_windows_terminal.ps1` |
| projet IA externe | dépôt `openclaw_openrouter` |
| matériel | `12_HARDWARE_QUALIFICATION.md` |
| maintenance | `15_MISES_A_JOUR.md` |
| sauvegarde | `10_BACKUP_RESTORE.md` |
| reconstruction | `13_RUNBOOK_REINSTALLATION.md` |

La règle de troubleshooting est toujours la même : **corriger la cause réelle, pas contourner le validateur**.
