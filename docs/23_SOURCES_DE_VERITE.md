# Sources de vérité du projet

Cette page définit la hiérarchie utilisée pour résoudre les divergences entre l'état réel, les contrats, les scripts, les rapports et la documentation.

```text
état réel observé + contrat versionné actuel -> validation
```

## Hiérarchie

1. état réel de la machine ;
2. configurations et manifests actuels ;
3. scripts et validateurs actuels ;
4. documentation active ;
5. logs et rapports ;
6. CHANGELOG et historique Git.

## Sources principales

| Domaine | Source |
| --- | --- |
| WSL2 | `config/wsl/runtime-contract.json` et `config/wsl/*.wslconfig` |
| Versions DevOps | `config/devops/tool-versions.env` |
| Windows Terminal | `config/windows-terminal/` |
| Déploiement Windows Terminal | `scripts/windows/31_windows_terminal.ps1` |
| Shell Bash / Starship Ubuntu | `config/wsl/bashrc.d/devops.sh`, `config/wsl/starship.toml` et `scripts/wsl/manage-devops-terminal.sh` |
| Matériel | `config/hardware/` |
| Windows | `config/windows/` |
| Defender | `config/defender/` |
| Sauvegarde | `config/backup/` |
| Applications | `manifests/winget/apps-core.json` |
| Orchestration | `install.ps1` + `scripts/core/runtime.psm1` |
| Interface humaine | `menu.ps1` |

Le contrat Windows Terminal est :

```text
PowerShell 7 - DevOps -> profil par défaut
Ubuntu - DevOps       -> accès explicite à la distribution Ubuntu WSL2
Ctrl+Shift+1          -> PowerShell 7 - DevOps
Ctrl+Shift+2          -> Ubuntu - DevOps
Ctrl+Shift+O          -> PowerShell + Ubuntu en panneaux
```

La configuration Windows Terminal ne possède pas le shell Bash d'Ubuntu : le profil Ubuntu ouvre simplement la distribution WSL2, dont le shell et Starship restent gérés par le contrat Linux existant.

## Projets externes

Il n'existe **aucune source de vérité OpenClaw/OpenRouter dans ce dépôt**. `config/openclaw/control-plane.json` et le bootstrap OpenClaw ne font pas partie de l'architecture de la workstation.

Les contrats OpenClaw, OpenRouter, `clawops`, Gateway, modèles et agents appartiennent au dépôt `mathiasseguincadiche/openclaw_openrouter`.

## Scripts

```text
scripts/core/
scripts/bootstrap/
scripts/windows/
scripts/wsl/
scripts/updates/
scripts/backup/
scripts/defender/
```

Aucun script de `Windows_11_Pro_Custom` ne doit cloner, installer, configurer ou valider OpenClaw/OpenRouter.

## Preuves

Les logs expliquent une exécution. Les rapports fournissent des preuves structurées. `state/` conserve certains états utiles au rollback. Aucun de ces éléments ne remplace une nouvelle observation et un `Verify` réussi.

preuves workstation distingue trois niveaux de preuve :

```text
STATIC     -> contrat vérifié sans workstation physique
SIMULATED  -> comportement exercé sur runner Windows ou environnement isolé
PHYSICAL   -> état vérifié sur la workstation réelle
```

Une CI verte ne doit jamais être présentée comme une preuve `PHYSICAL`. L'identité identité stockage, l'intégrité jalon historique, le matériel, WSL réel, le réseau et les exercices de sauvegarde/restauration exigent la machine physique.

L'empreinte `scripts/windows/90_workstation_fingerprint.ps1` est une **preuve de dérive** : elle compare un état physique approuvé à un état ultérieur. Elle ne devient pas une source de vérité supérieure aux contrats et ne doit jamais être remplacée pour masquer un écart inexpliqué.

Référence : [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md).

## Documentation et CI

La documentation active doit décrire le comportement actuel. La CI vérifie les contrats du dépôt et doit empêcher le retour de responsabilités OpenClaw/OpenRouter dans la workstation.

Les workflows historiques Vxx restent actifs tant qu'une migration de leurs protections n'a pas été explicitement prouvée. Le workflow consolidé preuves workstation ajoute une vue transversale sans supprimer ces contrôles.

```text
MACHINE RÉELLE     -> vérité observée
CONFIG / MANIFESTS -> état attendu
SCRIPTS             -> observation et convergence
VERIFY              -> décision de conformité
LOGS / REPORTS      -> preuves
DOCS                -> explication officielle
CHANGELOG / GIT     -> historique
```
