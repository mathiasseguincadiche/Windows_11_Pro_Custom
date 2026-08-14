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

- [ ] `C:` contient Windows ;
- [ ] `D:` est le volume NTFS attendu ;
- [ ] WSL est sous `D:\WSL\Ubuntu-DevOps` ;
- [ ] le filesystem Linux est fourni par le VHDX WSL2 ;
- [ ] le support de sauvegarde est distinct des SSD internes.

## 5. WSL2

- [ ] distribution `Ubuntu` en WSL2 ;
- [ ] Ubuntu 26.04 / `resolute` ;
- [ ] emplacement conforme ;
- [ ] profil `.wslconfig` conforme ;
- [ ] systemd fonctionne ;
- [ ] les projets vivent sous `~/projects`, `~/labs` ou `~/repositories` ;
- [ ] `/mnt/c` et `/mnt/d` ne sont pas les racines quotidiennes des projets Linux.

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

## 7. WezTerm et VS Code

- [ ] WezTerm est disponible ;
- [ ] `%USERPROFILE%\.wezterm.lua` correspond à la configuration versionnée ;
- [ ] `Ubuntu DevOps (WSL2)` est le profil par défaut ;
- [ ] `PowerShell 7` reste disponible ;
- [ ] aucun profil ou hook OpenClaw/`clawops` n'est possédé par la workstation ;
- [ ] VS Code ouvre les projets WSL sous `/home/<user>/...`.

```powershell
.\install.ps1 -Mode Verify
```

## 8. Frontière avec les projets externes

- [ ] `install.ps1` n'expose pas `InstallOpenClawAI` ou `ValidateOpenClawAI` ;
- [ ] `menu.ps1` ne propose pas d'installation OpenClaw/OpenRouter ;
- [ ] `scripts/bootstrap/15_openclaw_ai.ps1` est absent ;
- [ ] `config/openclaw/control-plane.json` est absent ;
- [ ] la conformité de la workstation ne dépend pas de `D:\AI\OpenClaw` ;
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

# Verdict final

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

Puis vérifier l'idempotence avec `-FullInstall -PlanOnly` et la sauvegarde de référence.

Le résultat attendu est une workstation **cohérente, performante, maintenable, reproductible et récupérable**, indépendante des projets applicatifs ou IA éventuellement utilisés dessus.
