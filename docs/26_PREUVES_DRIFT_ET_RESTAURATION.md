# V26 — Niveaux de preuve, dérive et restauration contrôlée

V26 renforce la preuve de conformité sans modifier l'architecture de la workstation ni affaiblir les garde-fous V24/V25.

## Niveaux de preuve

Le projet distingue désormais trois niveaux. Ils ne sont pas interchangeables.

| Niveau | Signification | Exemples |
| --- | --- | --- |
| `STATIC` | contrat vérifiable sans workstation physique | parsing PowerShell, JSON/YAML, cohérence documentation/manifeste, interdictions de sécurité |
| `SIMULATED` | comportement vérifié sur un runner Windows ou un environnement isolé | PowerShell natif, aliases WindowsApps, codes de sortie, contrats d'orchestration |
| `PHYSICAL` | preuve produite uniquement sur la workstation réelle | identité V25, intégrité V24, GPU/pilotes, WSL réel, réseau, backup et restauration isolée |

Une CI verte prouve les niveaux `STATIC` et une partie de `SIMULATED`. Elle ne remplace jamais un `Verify` réussi sur la machine physique.

## Empreinte globale de workstation

`scripts/windows/90_workstation_fingerprint_v26.ps1` produit une empreinte structurée et non destructive de l'état observable :

- version/build Windows ;
- CPU, mémoire, carte mère et GPU détectés ;
- présence et versions WSL ;
- hash SHA-256 de la baseline V25 locale si elle existe ;
- hash déterministe des contrats versionnés sous `config/` et `manifests/`.

La sortie est écrite sous `reports/workstation-v26/` et accompagnée d'un SHA-256.

```powershell
.\scripts\windows\90_workstation_fingerprint_v26.ps1 -Mode Audit
```

Après une validation physique complète et uniquement sur un état sain, une baseline locale peut être enregistrée :

```powershell
.\scripts\windows\90_workstation_fingerprint_v26.ps1 `
  -Mode Record `
  -ConfirmHealthyState
```

Puis comparée après maintenance ou Windows Update :

```powershell
.\scripts\windows\90_workstation_fingerprint_v26.ps1 -Mode Verify
```

La baseline locale est conservée sous :

```text
%ProgramData%\Windows11ProCustom\workstation-v26\workstation-fingerprint.json
```

Elle ne remplace aucune source de vérité. Une différence est un signal de dérive à expliquer, pas une autorisation de forcer la convergence.

## Test de restauration WSL isolé

`scripts/backup/63_restore_drill_v26.ps1` valide une session Golden Backup sans toucher à la distribution WSL de production.

Mode lecture seule :

```powershell
.\scripts\backup\63_restore_drill_v26.ps1 `
  -BackupSessionPath 'E:\Windows_11_Pro_Custom_Backup\V7\20260817-120000' `
  -Mode Verify
```

Le mode `Verify` contrôle le manifeste, le VHDX et son SHA-256, la copie de baseline V25 et l'énumérabilité de la sauvegarde Windows.

Pour prouver qu'un VHDX WSL est réellement amorçable, le mode `Sandbox` :

1. copie le VHDX vers un répertoire temporaire distinct ;
2. l'importe sous un nom de distribution temporaire unique ;
3. vérifie `/etc/os-release`, le filesystem racine et l'accès shell ;
4. désenregistre uniquement la distribution temporaire dans un bloc `finally` ;
5. supprime uniquement la copie temporaire créée par le drill.

Il exige une confirmation explicite :

```powershell
.\scripts\backup\63_restore_drill_v26.ps1 `
  -BackupSessionPath 'E:\Windows_11_Pro_Custom_Backup\V7\20260817-120000' `
  -Mode Sandbox `
  -ScratchRoot 'D:\WSL-RestoreDrill' `
  -ConfirmIsolatedRestoreDrill
```

Le script refuse d'utiliser `Ubuntu` comme nom temporaire et ne contient aucun chemin qui désenregistre la distribution de production.

## Limite volontaire : restauration Windows

Une image `wbadmin` de `C:`/`D:` ne peut pas être restaurée de manière sûre sur la workstation active uniquement pour « tester ». V26 vérifie donc qu'une version est énumérable et conserve le test de restauration Windows complet comme exercice **WinRE/offline** planifié.

Une sauvegarde est considérée plus forte lorsqu'elle cumule :

```text
création réussie
+ validation SHA-256
+ wbadmin get versions réussi
+ restauration WSL sandbox réussie
+ exercice WinRE/offline documenté périodiquement
```

## Politique CI

V26 ajoute un workflow consolidé `workstation-evidence-v26.yml`. Il ne remplace ni ne supprime les workflows historiques existants dans cette évolution afin d'éviter une régression de couverture. La consolidation des noms Vxx pourra être effectuée séparément lorsque les protections de branche et références documentaires auront été inventoriées.
