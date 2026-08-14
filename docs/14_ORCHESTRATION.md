# Orchestration — état réel, plan, convergence et idempotence

L'orchestration gère la workstation sans supposer qu'elle est vide et sans réappliquer aveuglément les mêmes actions.

```powershell
.\install.ps1
```

## Modèle

```text
état attendu + état réel
↓
Verify
↓
plan factuel
↓
DÉJÀ OK ou Apply ciblé
↓
re-Verify
↓
logs + verdict
```

`install.ps1` s'appuie sur `scripts/core/runtime.psm1`. Les fichiers `state/` servent au rollback, jamais à prouver la conformité actuelle.

## Modes

```powershell
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Apply
.\install.ps1 -Mode Verify
.\install.ps1 -Mode Rollback
```

`Audit` observe. `Apply` vérifie puis corrige le delta. `Verify` exige la conformité. `Rollback` ne restaure que les états que le dépôt sait réellement remettre en place.

## `FullInstall`

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

Active uniquement :

```text
InstallDevOps
ValidateDevOps
ValidateWsl
ValidateHardware
```

Il ne déclenche aucun projet externe.

## `PlanOnly`

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Observe et calcule le plan sans appliquer de modification.

## WSL2 et DevOps

WSL vérifie la distribution, le mode WSL2, le profil, l'emplacement sous `D:` et la release attendue.

La stack DevOps peut être demandée séparément :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

## Frontière OpenClaw/OpenRouter

OpenClaw/OpenRouter n'est pas un composant de l'orchestrateur. `Windows_11_Pro_Custom` ne possède ni paramètre d'installation OpenClaw, ni pin de control-plane, ni bootstrap OpenClaw.

Le dépôt `mathiasseguincadiche/openclaw_openrouter` possède son installation, sa configuration et sa validation avec ses propres points d'entrée.

Voir [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

## Preuves

```text
logs\install.log
logs\<catégorie>\<script>.log
logs\runs\<RunId>\events.ndjson
logs\runs\<RunId>\summary.json
reports\orchestration\latest-run.json
```

## Maintenance

`install.ps1` gère la conformité. `update.ps1` gère la maintenance Windows, WinGet, WSL, Ubuntu, DevOps et VS Code.

```text
observer → planifier → appliquer le nécessaire → re-vérifier
```

La qualification finale est détaillée dans [`11_VALIDATION.md`](11_VALIDATION.md), [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) et [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md).
