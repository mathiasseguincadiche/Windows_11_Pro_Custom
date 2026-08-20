# preuves workstation — Niveaux de preuve, dérive et restauration contrôlée

preuves workstation renforce la preuve de conformité sans modifier l'architecture de la workstation ni affaiblir les garde-fous jalon historique/identité stockage.

## Niveaux de preuve

Le projet distingue désormais trois niveaux. Ils ne sont pas interchangeables.

| Niveau | Signification | Exemples |
| --- | --- | --- |
| `STATIC` | contrat vérifiable sans workstation physique | parsing PowerShell, JSON/YAML, cohérence documentation/manifeste, interdictions de sécurité |
| `SIMULATED` | comportement vérifié sur un runner Windows ou un environnement isolé | PowerShell natif, aliases WindowsApps, codes de sortie, contrats d'orchestration |
| `PHYSICAL` | preuve produite uniquement sur la workstation réelle | identité identité stockage, intégrité jalon historique, GPU/pilotes, WSL réel, réseau, backup et restauration isolée |

Une CI verte prouve les niveaux `STATIC` et une partie de `SIMULATED`. Elle ne remplace jamais un `Verify` réussi sur la machine physique.

## Empreinte globale de workstation

`scripts/windows/90_workstation_fingerprint.ps1` produit une empreinte structurée et non destructive de l'état observable :

- version/build Windows ;
- CPU, mémoire, carte mère et GPU détectés ;
- présence et versions WSL ;
- hash SHA-256 de la baseline d’identité stockage locale si elle existe ;
- hash déterministe des contrats versionnés sous `config/` et `manifests/`.

La sortie est écrite sous `reports/workstation/` et accompagnée d'un SHA-256.

Un audit sans confirmation explicite produit une preuve `SIMULATED`, y compris
sur un runner Windows :

```powershell
.\scripts\windows\90_workstation_fingerprint.ps1 -Mode Audit
```

Sur la workstation réelle uniquement, la preuve physique est demandée
explicitement :

```powershell
.\scripts\windows\90_workstation_fingerprint.ps1 `
  -Mode Audit `
  -EvidenceLevel PHYSICAL `
  -ConfirmPhysicalEvidence
```

Après une validation physique complète et uniquement sur un état sain, une baseline locale peut être enregistrée :

```powershell
.\scripts\windows\90_workstation_fingerprint.ps1 `
  -Mode Record `
  -EvidenceLevel PHYSICAL `
  -ConfirmPhysicalEvidence `
  -ConfirmHealthyState
```

Puis comparée après maintenance ou Windows Update :

```powershell
.\scripts\windows\90_workstation_fingerprint.ps1 `
  -Mode Verify `
  -EvidenceLevel PHYSICAL `
  -ConfirmPhysicalEvidence
```

Une maintenance intentionnelle peut nécessiter un nouvel enrôlement. Le
remplacement reste explicite, exige une raison et archive la baseline précédente
avec le diff complet :

```powershell
.\scripts\windows\90_workstation_fingerprint.ps1 `
  -Mode Record `
  -EvidenceLevel PHYSICAL `
  -ConfirmPhysicalEvidence `
  -ConfirmHealthyState `
  -ReplaceBaseline `
  -ReplacementReason 'Windows Update validé et requalification complète réussie'
```

La baseline locale est conservée sous :

```text
%ProgramData%\Windows11ProCustom\workstation-v26\workstation-fingerprint.json
%ProgramData%\Windows11ProCustom\workstation-v26\workstation-fingerprint.json.sha256
```

Toute nouvelle baseline reçoit un sidecar SHA-256, vérifié avant comparaison ou
remplacement. Une baseline créée avant ce durcissement reste lisible avec le
statut `LEGACY_UNVERIFIED`; un remplacement contrôlé après requalification est
alors recommandé. Le sidecar rend les corruptions accidentelles détectables,
mais ne remplace pas une signature cryptographique protégée hors de la machine.

Elle ne remplace aucune source de vérité. Une différence est un signal de dérive
à expliquer, pas une autorisation de forcer la convergence. Le rapport de dérive
indique les champs attendus et actuels ; l'empreinte contient également le commit
Git du dépôt lorsqu'il est disponible.

## Test de restauration WSL isolé

`scripts/backup/63_restore_drill.ps1` valide une session Golden Backup sans toucher à la distribution WSL de production.

Mode lecture seule :

```powershell
.\scripts\backup\63_restore_drill.ps1 `
  -BackupSessionPath 'F:\Windows_11_Pro_Custom_Backup\sessions\20260817-120000' `
  -Mode Verify
```

Le mode `Verify` contrôle le manifeste, le VHDX et son SHA-256, la copie de
baseline d’identité stockage et la présence de la version `wbadmin` exacte liée au manifeste.
Une session créée avant l'ajout de cet identifiant reste vérifiable, mais reçoit
un avertissement indiquant que seule l'énumérabilité globale est prouvée.

Pour prouver qu'un VHDX WSL est réellement amorçable, le mode `Sandbox` :

1. vérifie que le volume temporaire dispose de la taille du VHDX, de 10 % de marge et de 1 Go supplémentaire ;
2. copie le VHDX vers un répertoire temporaire distinct ;
3. l'importe sous un nom de distribution temporaire unique ;
4. vérifie `/etc/os-release`, le filesystem racine et l'accès shell ;
5. désenregistre uniquement la distribution temporaire dans un bloc `finally` et vérifie sa disparition ;
6. supprime uniquement la copie temporaire créée par le drill, après confirmation du désenregistrement.

Si le désenregistrement échoue ou ne peut pas être confirmé, le drill échoue et
conserve volontairement la copie scratch afin de ne jamais supprimer le VHDX
d'une distribution encore enregistrée.

Il exige une confirmation explicite :

```powershell
.\scripts\backup\63_restore_drill.ps1 `
  -BackupSessionPath 'F:\Windows_11_Pro_Custom_Backup\sessions\20260817-120000' `
  -Mode Sandbox `
  -ScratchRoot 'E:\WSL-RestoreDrill' `
  -ConfirmIsolatedRestoreDrill
```

Le script refuse d'utiliser `Ubuntu` comme nom temporaire et ne contient aucun chemin qui désenregistre la distribution de production.

## Limite volontaire : restauration Windows

Une image `wbadmin` de `C:`/`E:` ne peut pas être restaurée de manière sûre sur la workstation active uniquement pour « tester ». preuves workstation vérifie donc qu'une version est énumérable et conserve le test de restauration Windows complet comme exercice **WinRE/offline** planifié.

Une sauvegarde est considérée plus forte lorsqu'elle cumule :

```text
création réussie
+ validation SHA-256
+ wbadmin get versions réussi
+ restauration WSL sandbox réussie
+ exercice WinRE/offline documenté périodiquement
```

## Politique CI

preuves workstation ajoute un workflow consolidé `workstation-evidence-v26.yml`. Il ne remplace ni ne supprime les workflows historiques existants dans cette évolution afin d'éviter une régression de couverture. La consolidation des noms Vxx pourra être effectuée séparément lorsque les protections de branche et références documentaires auront été inventoriées.
