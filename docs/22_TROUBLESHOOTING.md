# Troubleshooting — diagnostiquer la workstation par domaine

Ce guide décrit comment diagnostiquer un écart de `Windows_11_Pro_Custom` sans mélanger les responsabilités. Avant toute correction, identifier la source de vérité avec [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

## Méthode générale

```text
observer → identifier le domaine propriétaire → lire les preuves
→ comparer au contrat → appliquer le delta compris → revalider
```

## Orchestration

### `Audit` fonctionne mais `Verify` échoue

```text
Audit  -> observe et décrit
Verify -> exige la conformité
```

Identifier le composant en échec, lire son contrat, appliquer un `Apply` ciblé si nécessaire puis relancer `Verify`.

### Le même composant revient toujours dans le plan

Vérifier que `Verify` teste bien l'état produit par `Apply`, que la configuration générée est stable et qu'aucune étape externe ne modifie cet état après convergence.

## WSL2

```powershell
wsl --status
wsl --version
.\install.ps1 -Mode Verify -ValidateWsl
```

Le contrat attend Ubuntu 26.04 / `resolute`, en WSL2, sous `D:\WSL\Ubuntu-DevOps`.

## Stack DevOps

La source de vérité des versions est `config/devops/tool-versions.env`.

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
.\install.ps1 -Mode Verify -ValidateDevOps
```

Docker n'est qu'un élément de la qualification : vérifier aussi Compose/Buildx, Kubernetes, Terraform/Ansible, AWS/GitHub CLI et les outils qualité.

## WezTerm et expérience terminal

La source de vérité est `config/wezterm/wezterm.lua`.

Le contrat attendu est :

```text
Ubuntu DevOps (WSL2) <- défaut
PowerShell 7
```

Validation :

```powershell
.\install.ps1 -Mode Verify
```

Si `%USERPROFILE%\.wezterm.lua` diffère, utiliser le parcours `Audit` / `Apply` / `Verify` plutôt que de maintenir plusieurs copies manuellement.

## VS Code

Pour un projet Linux, vérifier que VS Code est relié à WSL et que le chemin actif est sous `/home/<user>/...`.

## OpenClaw/OpenRouter

Ce domaine est **hors périmètre**. `Windows_11_Pro_Custom` ne possède ni son installation, ni sa configuration, ni ses diagnostics.

Pour tout problème OpenClaw, OpenRouter, `clawops`, Gateway, modèles ou agents, utiliser exclusivement le dépôt `mathiasseguincadiche/openclaw_openrouter` et sa documentation.

Le dépôt Windows ne doit pas contenir de `config/openclaw/control-plane.json`, de bootstrap OpenClaw ou de paramètre `ValidateOpenClawAI`.

Voir [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

## Matériel et stockage

Qualification matérielle :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

Pour `D:`, vérifier la lettre, le filesystem, l'espace disponible et les chemins réellement observés avant toute correction.

## Maintenance

```powershell
.\update.ps1 -Mode Audit
```

Lire ensuite `reports\updates\latest-run.json` et revalider uniquement les domaines concernés.

## Sauvegarde

Une sauvegarde non vérifiée ne compte pas comme critère d'acceptation rempli. Vérifier le support, sa capacité, les données nécessaires et l'export WSL prévu.

## CI GitHub

Le workflow `Documentation` contrôle la cohérence des documents et des interfaces publiques. `quality`, `runtime-smoke` et `DevOps terminal` contrôlent les scripts, configurations et frontières du dépôt.

La CI doit notamment refuser le retour d'une intégration OpenClaw/OpenRouter dans l'orchestrateur ou le terminal de la workstation.

## Reconstruction

Tant que la workstation existe et qu'un composant est simplement incohérent :

```text
Audit -> Plan -> Apply ciblé -> Verify
```

Pour une reconstruction réelle, utiliser [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md). Le parcours quotidien reste [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).
