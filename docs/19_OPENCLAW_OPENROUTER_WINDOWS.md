# OpenClaw + OpenRouter sous Windows 11 — installation propre sur D:

Cette intégration ajoute la pile IA du dépôt privé `mathiasseguincadiche/openclaw_openrouter` au poste `Windows_11_Pro_Custom` sans la mélanger avec WSL2.

## Architecture retenue

```text
C:\
└── Windows 11 Pro + applications système

D:\WSL\
└── Ubuntu-DevOps\
    └── Docker, Kubernetes, Terraform, Ansible et outils Linux

D:\AI\OpenClaw\
├── control-plane\     # checkout Git du dépôt openclaw_openrouter
├── npm-global\        # runtime npm OpenClaw
├── state\             # configuration, credentials, sessions et état OpenClaw
├── workspace\         # workspace principal
├── clawops\           # projets, intake et état du toolkit
├── venv\              # Python + CLI clawops
├── logs\
└── cache\
```

La règle est donc simple :

```text
DevOps Linux -> D:\WSL
IA OpenClaw -> D:\AI\OpenClaw
Windows     -> C:\
```

## Pourquoi OpenClaw reste natif Windows

Le poste conserve WSL2 pour les workloads Linux DevOps, mais la pile OpenClaw est installée directement sous Windows. Cela évite de placer l'état IA, les credentials et les workspaces dans le VHDX Ubuntu alors que le projet IA est destiné à être un service de poste autonome.

## Audit

Depuis PowerShell 7 :

```powershell
.\install.ps1 -Mode Audit
```

L'audit contrôle notamment :

- le volume `D:` et son filesystem NTFS ;
- la présence éventuelle du checkout `D:\AI\OpenClaw\control-plane` ;
- la présence des launchers OpenClaw et `clawops` ;
- les variables utilisateur persistées.

## Installation depuis le socle Windows

```powershell
.\install.ps1 -Mode Apply -InstallOpenClawAI
```

Le bootstrap `scripts/bootstrap/15_openclaw_ai.ps1` :

1. vérifie que la cible est `D:` en NTFS ;
2. installe Git for Windows via WinGet si nécessaire ;
3. clone ou met à jour le dépôt privé `openclaw_openrouter` sous `D:\AI\OpenClaw\control-plane` ;
4. refuse de mettre à jour un checkout contenant des modifications locales ;
5. appelle l'installateur Windows versionné par le dépôt IA ;
6. laisse les secrets hors de Git.

Le dépôt IA étant privé, Git Credential Manager doit être authentifié auprès de GitHub lors du premier clone.

## Installation directe du dépôt IA

Depuis un checkout déjà présent :

```powershell
.\scripts\windows\00_install_openclaw_windows.ps1 -Mode Apply
```

Cet installateur :

- installe Node.js LTS si nécessaire ;
- installe Python 3.13 si aucun Python 3.11+ compatible n'est disponible ;
- installe OpenClaw avec un préfixe npm isolé sous `D:\AI\OpenClaw\npm-global` ;
- crée le virtualenv `clawops` sous `D:\AI\OpenClaw\venv` ;
- configure les chemins persistants OpenClaw et `clawops` sur `D:`.

## Variables persistées

```text
OPENCLAW_HOME=D:\AI\OpenClaw
OPENCLAW_STATE_DIR=D:\AI\OpenClaw\state
OPENCLAW_CONFIG_PATH=D:\AI\OpenClaw\state\openclaw.json
OPENCLAW_WORKSPACE_DIR=D:\AI\OpenClaw\workspace
CLAWOPS_HOME=D:\AI\OpenClaw\clawops
CLAWOPS_DEPLOYMENT_MODE=windows-native
```

## OpenRouter

L'installation Windows ne demande pas automatiquement une clé API afin d'éviter toute automatisation maladroite des secrets.

Après l'installation :

```powershell
openclaw onboard --auth-choice openrouter-api-key
```

Puis :

```powershell
clawops validate config
clawops validate models
clawops budget status
clawops team deploy
clawops team status
```

## Gateway

L'installation du Gateway est volontairement séparée du bootstrap Windows principal.

Après qualification :

```powershell
openclaw gateway install
openclaw gateway status --json
```

L'exposition réseau ne doit pas être élargie sans besoin explicite.

## Qualification

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

Verdict attendu :

```text
VERDICT: OPENCLAW AI READY
```

La validation du dépôt IA ajoute également :

```text
VERDICT: OPENCLAW WINDOWS D DRIVE READY
```

## Développement de la branche d'intégration

Tant que l'adaptation Windows du dépôt `openclaw_openrouter` n'est pas encore fusionnée dans son `main`, la branche peut être testée explicitement :

```powershell
.\install.ps1 `
  -Mode Apply `
  -InstallOpenClawAI `
  -OpenClawRepositoryRef feat/windows-11-d-drive
```

Après fusion de la PR du dépôt IA, la valeur par défaut `main` redevient suffisante.

## Rollback

`install.ps1 -Mode Rollback` ne supprime jamais automatiquement `D:\AI\OpenClaw`.

C'est volontaire : `state` peut contenir des credentials, des sessions et des données de travail. Une suppression ou migration de cet état doit être une décision explicite et précédée d'une sauvegarde.

## Sauvegarde

La stratégie V7 de ce dépôt image déjà les volumes `C:` et `D:`. Le répertoire `D:\AI\OpenClaw` est donc inclus dans la protection du volume DATA.

Les sauvegardes contenant `D:\AI\OpenClaw\state` doivent être considérées comme sensibles et stockées sur un support de confiance.