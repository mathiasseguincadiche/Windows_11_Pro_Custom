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
| WezTerm | `config/wezterm/wezterm.lua` |
| Déploiement WezTerm | `scripts/windows/31_wezterm.ps1` |
| Matériel | `config/hardware/` |
| Windows | `config/windows/` |
| Defender | `config/defender/` |
| Sauvegarde | `config/backup/` |
| Applications | `manifests/winget/apps-core.json` |
| Orchestration | `install.ps1` + `scripts/core/runtime.psm1` |
| Interface humaine | `menu.ps1` |

Le contrat terminal est :

```text
Ubuntu DevOps (WSL2) -> profil par défaut
PowerShell 7         -> administration Windows
```

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

## Documentation et CI

La documentation active doit décrire le comportement actuel. La CI vérifie les contrats du dépôt et doit empêcher le retour de responsabilités OpenClaw/OpenRouter dans la workstation.

```text
MACHINE RÉELLE     -> vérité observée
CONFIG / MANIFESTS -> état attendu
SCRIPTS             -> observation et convergence
VERIFY              -> décision de conformité
LOGS / REPORTS      -> preuves
DOCS                -> explication officielle
CHANGELOG / GIT     -> historique
```
