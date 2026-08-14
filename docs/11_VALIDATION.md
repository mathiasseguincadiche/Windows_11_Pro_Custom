# Validation — prouver que la workstation est réellement prête

La validation transforme une installation en **résultat démontré**. La conformité vient de l'état réel observé, des contrats versionnés, des validateurs et des preuves générées.

```text
contrat attendu + état réel observé + preuve -> Verify réussi
```

Le Runbook est [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) et la checklist de sortie [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md).

## Audit, Apply et Verify

```powershell
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Apply
.\install.ps1 -Mode Verify
```

```text
Audit  -> comprendre
Plan   -> prévoir
Apply  -> corriger
Verify -> prouver
```

## Qualification matérielle

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

Le projet combine faits observables et preuves manuelles lorsque Windows ne peut pas déterminer honnêtement une information physique ou firmware.

Guide : [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

## Qualification WSL2

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

Contrat principal : Ubuntu 26.04 / `resolute`, WSL2, sous `D:\WSL\Ubuntu-DevOps`, avec HOME et projets sur filesystem Linux.

Guide : [`06_WSL2.md`](06_WSL2.md).

## Qualification DevOps

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

Elle couvre Docker/Compose/Buildx, Kubernetes CLI, Helm, Minikube/kind, Terraform, Ansible, AWS CLI, GitHub CLI et les outils qualité. Les versions reproductibles sont définies dans `config/devops/tool-versions.env`.

Guide : [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md).

## Qualification principale

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

OpenClaw/OpenRouter ne fait pas partie de ce verdict. Sa validation appartient exclusivement au dépôt `mathiasseguincadiche/openclaw_openrouter`.

## Preuves

```text
logs\install.log
logs\<catégorie>\<script>.log
logs\runs\<RunId>\events.ndjson
logs\runs\<RunId>\summary.json
reports\orchestration\latest-run.json
reports\orchestration\machine-state.json
```

Un ancien rapport n'est pas une preuve actuelle : la conformité est recalculée depuis la machine réelle.

## Idempotence

Après convergence :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Le résultat doit tendre vers `DÉJÀ OK`. Un composant qui revient sans cesse en `À FAIRE` indique une incohérence entre détection, Apply et Verify.

## Validation après maintenance

```powershell
.\update.ps1 -Mode Audit
.\update.ps1 -Mode Apply
.\update.ps1 -Mode Verify
```

Après une maintenance structurante, requalifier uniquement les domaines concernés.

## Validation et sauvegarde

Une fois la machine stabilisée : créer ou actualiser la sauvegarde de référence, la vérifier et confirmer qu'un plan de reprise peut être préparé.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

## Ce qu'un verdict positif ne doit jamais masquer

- un composant demandé ignoré ;
- une preuve matérielle remplacée par une supposition ;
- un contrat modifié uniquement pour faire passer l'état actuel ;
- une CI verte utilisée comme preuve du matériel réel ;
- un ancien fichier `state/` utilisé comme preuve ;
- une protection système désactivée pour faire disparaître un échec ;
- la validation d'un projet externe présent sur la même machine.

## Critères finaux

```text
Verify de base réussi
+ qualification matérielle
+ WSL2 conforme
+ stack DevOps conforme
+ actions humaines closes
+ idempotence cohérente
+ preuves disponibles
+ sauvegarde vérifiée
```

La checklist détaillée est [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md).
