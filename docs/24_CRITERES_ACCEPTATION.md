# Critères d'acceptation — quand le projet est réellement terminé

Cette page transforme le résultat attendu de `Windows_11_Pro_Custom` en critères concrets. Le projet est terminé lorsque l'état final de la **workstation** est conforme, vérifié, explicable et récupérable.

## 1. Dépôt et orchestration

- [ ] `install.ps1 -Mode Audit` produit des preuves exploitables ;
- [ ] `-PlanOnly` calcule un plan factuel ;
- [ ] les composants conformes restent `DÉJÀ OK` ;
- [ ] les actions humaines sont explicites ;
- [ ] une seconde planification ne repropose pas arbitrairement les mêmes modifications.

## 2. Windows 11 Pro

- [ ] Windows 11 Pro est l'hôte réel ;
- [ ] Windows Update et Microsoft Defender restent disponibles ;
- [ ] PowerShell 7 est disponible ;
- [ ] les applications et réglages gérés sont conformes.

## 3. Matériel

- [ ] AMD Ryzen 7 7700 détecté ;
- [ ] mémoire conforme au minimum attendu ;
- [ ] MSI MAG B850M Mortar WiFi identifiée ;
- [ ] Intel Arc B580 détectée avec pilote ;
- [ ] les deux Crucial T705 sont présents ;
- [ ] GPT/UEFI, Secure Boot, TPM et virtualisation sont qualifiés ;
- [ ] les preuves manuelles obligatoires sont renseignées.

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

## 4. Stockage

- [ ] `C:` contient Windows et correspond à l'identité physique identité stockage enrôlée ;
- [ ] `E:` est le volume NTFS attendu et correspond à l'identité physique identité stockage enrôlée ;
- [ ] `C:` et `E:` résident sur deux SSD physiques distincts ;
- [ ] la baseline d’identité stockage a été enregistrée après contrôle humain puis vérifiée ;
- [ ] le contrôle jalon historique confirme NTFS/NVMe sans corruption bloquante ;
- [ ] WSL est sous `E:\WSL\Ubuntu-DevOps` ;
- [ ] le filesystem Linux est fourni par le VHDX WSL2 ;
- [ ] le support de sauvegarde est distinct des SSD internes.

```powershell
.\scripts\bootstrap\00_storage_identity.ps1 -Mode Verify
.\scripts\bootstrap\00_storage_integrity.ps1 -Mode Verify
```

Guide : [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md).

## 5. WSL2

- [ ] distribution `Ubuntu` en WSL2 ;
- [ ] Ubuntu 26.04 / `resolute` ;
- [ ] emplacement conforme ;
- [ ] profil `.wslconfig` conforme ;
- [ ] systemd fonctionne ;
- [ ] les projets vivent sous `~/projects`, `~/labs` ou `~/repositories` ;
- [ ] `/mnt/c` et `/mnt/e` restent accessibles pour des échanges ponctuels avec Windows mais sont **interdits comme racines de projets ou de workspaces DevOps**.

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

## 6. Stack DevOps

- [ ] Docker Engine / Compose / Buildx conformes ;
- [ ] kubectl / Helm / Minikube / kind conformes ;
- [ ] Terraform / Ansible disponibles ;
- [ ] AWS CLI / GitHub CLI disponibles ;
- [ ] outils qualité attendus disponibles ;
- [ ] versions épinglées conformes à `config/devops/tool-versions.env`.

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

## 7. Windows Terminal et VS Code

- [ ] Windows Terminal est disponible via `Microsoft.WindowsTerminal` et satisfait la version minimale du contrat moderne ;
- [ ] Windows Terminal Stable est l'application terminal système par défaut ;
- [ ] Starship Windows et `JetBrainsMono Nerd Font` sont disponibles ;
- [ ] le fragment géré expose exactement `PowerShell 7 - DevOps`, `PowerShell 7 - DevOps (Admin)` et `Ubuntu - DevOps` ;
- [ ] `PowerShell 7 - DevOps` est le profil Windows Terminal par défaut et n'est pas élevé ;
- [ ] `PowerShell 7 - DevOps (Admin)` utilise `elevate=true` et possède une identité visuelle distincte ;
- [ ] `Ubuntu - DevOps` démarre explicitement dans `~` ;
- [ ] les trois profils empêchent l'application courante d'écraser un titre d'onglet renommé ;
- [ ] `Ctrl+T` ouvre un nouvel onglet PowerShell 7 - DevOps ;
- [ ] `Ctrl+Shift+1` ouvre PowerShell 7 - DevOps ;
- [ ] `Ctrl+Shift+2` ouvre Ubuntu - DevOps ;
- [ ] `Ctrl+Shift+3` ouvre PowerShell 7 - DevOps (Admin) ;
- [ ] `Ctrl+Shift+R` ouvre le renommage natif de l'onglet courant ;
- [ ] `Ctrl+W` ferme l'onglet courant ;
- [ ] `Ctrl+Shift+O` ouvre PowerShell et Ubuntu en panneaux ;
- [ ] le menu `+` regroupe les profils Windows 11 Pro Custom tout en conservant les profils tiers ;
- [ ] le thème `WPC DevOps` utilise Mica et les profils normal/Admin/Ubuntu utilisent leurs schémas gérés ;
- [ ] le bloc PowerShell/Starship géré est présent une seule fois, force UTF-8 et configure PSReadLine ;
- [ ] la transformation de `settings.json` est idempotente et préserve les réglages utilisateur non possédés ;
- [ ] `Apply` sauvegarde les fichiers et la délégation terminal système avant mutation ;
- [ ] le composant Windows Terminal passe `Audit / Apply / Verify / Rollback` et restaure l'état initial enregistré ;
- [ ] le shell Bash/Starship Ubuntu reste possédé par les scripts WSL et n'est pas réécrit par le composant Windows Terminal ;
- [ ] aucun profil ou hook OpenClaw/`clawops` n'est possédé par la workstation ;
- [ ] VS Code ouvre les projets WSL sous `/home/<user>/...`.

```powershell
.\scripts\windows\31_windows_terminal.ps1 -Mode Verify
```

## 8. Frontière avec les projets externes

- [ ] `install.ps1` n'expose pas `InstallOpenClawAI` ou `ValidateOpenClawAI` ;
- [ ] `menu.ps1` ne propose pas d'installation OpenClaw/OpenRouter ;
- [ ] `scripts/bootstrap/15_openclaw_ai.ps1` est absent ;
- [ ] `config/openclaw/control-plane.json` est absent ;
- [ ] la conformité de la workstation ne dépend pas de `E:\AI\OpenClaw` ;
- [ ] OpenClaw/OpenRouter est installé et configuré uniquement depuis `mathiasseguincadiche/openclaw_openrouter` lorsqu'il est utilisé.

## 9. Maintenance, preuves et idempotence

- [ ] `update.ps1 -Mode Audit` produit un état compréhensible ;
- [ ] les logs et rapports permettent d'expliquer les verdicts ;
- [ ] aucun secret n'est volontairement journalisé ;
- [ ] `FullInstall` est idempotent.

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

## 10. Sauvegarde et reprise

- [ ] une sauvegarde de référence existe sur un support séparé ;
- [ ] sa structure et sa capacité sont vérifiées ;
- [ ] l'export WSL prévu est inclus ;
- [ ] un plan de reprise peut être préparé.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

## 11. Preuves preuves workstation, dérive et restaurabilité

- [ ] les preuves `STATIC`, `SIMULATED` et `PHYSICAL` ne sont pas confondues ;
- [ ] une CI verte n'est pas considérée comme une preuve physique ;
- [ ] `90_workstation_fingerprint.ps1 -Mode Audit` produit une preuve `SIMULATED`, un rapport structuré et son SHA-256 ;
- [ ] une preuve `PHYSICAL` exige `-EvidenceLevel PHYSICAL -ConfirmPhysicalEvidence` sur la workstation réelle ;
- [ ] une baseline preuves workstation n'est enregistrée qu'après validation physique complète et possède un sidecar SHA-256 valide ;
- [ ] `-Mode Verify` ne signale aucune dérive inexpliquée ;
- [ ] un remplacement de baseline est justifié, archivé et accompagné d'un diff ;
- [ ] le Golden Backup passe `63_restore_drill.ps1 -Mode Verify` ;
- [ ] au moins un drill WSL `Sandbox` a prouvé que le VHDX peut être importé et démarré sans toucher à la distribution `Ubuntu` réelle ; en cas d'échec du désenregistrement temporaire, le VHDX scratch n'est pas supprimé ;
- [ ] l'exercice de restauration Windows complet reste planifié sous WinRE/offline et n'est jamais automatisé sur le système actif.

```powershell
.\scripts\windows\90_workstation_fingerprint.ps1 `
  -Mode Audit `
  -EvidenceLevel PHYSICAL `
  -ConfirmPhysicalEvidence
```

Guide : [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md).

# Verdict final

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

Puis vérifier l'idempotence avec `-FullInstall -PlanOnly`, la sauvegarde de référence et l'absence de dérive preuves workstation inexpliquée.

Le résultat attendu est une workstation **cohérente, performante, maintenable, reproductible et récupérable**, indépendante des projets applicatifs ou IA éventuellement utilisés dessus.
