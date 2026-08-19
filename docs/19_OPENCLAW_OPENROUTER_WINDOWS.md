# OpenClaw/OpenRouter — projet externe, hors périmètre de la workstation

Ce document existe uniquement pour fixer une frontière d'architecture claire entre `Windows_11_Pro_Custom` et le projet IA `mathiasseguincadiche/openclaw_openrouter`.

## Règle de responsabilité

`Windows_11_Pro_Custom` construit, configure, valide et maintient la **workstation Windows 11 Pro / WSL2 / DevOps**.

Il ne doit pas :

- installer OpenClaw ;
- configurer OpenRouter ;
- installer ou maintenir `clawops` ;
- installer le Gateway OpenClaw ;
- cloner ou synchroniser le dépôt `openclaw_openrouter` ;
- posséder un pin ou un runtime lock OpenClaw ;
- gérer les modèles, agents, budgets ou politiques IA ;
- valider la plateforme IA ;
- exposer de paramètres `InstallOpenClawAI` ou `ValidateOpenClawAI` dans `install.ps1`.

Ces responsabilités appartiennent **entièrement** au dépôt :

```text
mathiasseguincadiche/openclaw_openrouter
```

## Frontière entre les deux dépôts

```text
Windows_11_Pro_Custom
├── Windows 11 Pro
├── pilotes / sécurité / mises à jour
├── PowerShell / WinGet
├── Windows Terminal
├── WSL2 Ubuntu 26.04
├── stack DevOps Linux
├── VS Code
├── stockage / sauvegarde / restauration
└── validation de la workstation

openclaw_openrouter
├── installation OpenClaw
├── configuration OpenRouter
├── clawops
├── Gateway
├── modèles
├── agents
├── runtime lock
├── orchestration IA
└── validation de la plateforme IA
```

Les deux projets peuvent naturellement être utilisés sur la même machine, mais **aucun n'a besoin de devenir l'orchestrateur de l'autre**.

## Conséquence pour `-FullInstall`

Dans `Windows_11_Pro_Custom` :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

signifie uniquement :

```text
workstation Windows
+ Windows Terminal
+ WSL2
+ stack DevOps
+ qualification WSL
+ qualification DevOps
+ qualification matérielle
```

Aucune installation ou configuration OpenClaw/OpenRouter n'est déclenchée.

## Windows Terminal

La configuration Windows Terminal gérée par ce dépôt expose uniquement les contextes de la workstation :

```text
PowerShell 7 - DevOps
Ubuntu - DevOps
```

Le composant `scripts/windows/31_windows_terminal.ps1` ne contient aucun profil, hook ou raccourci spécifique à OpenClaw, OpenRouter ou `clawops`.

Si `openclaw_openrouter` souhaite ajouter une expérience terminal spécifique à sa plateforme, cette intégration doit être possédée et documentée par le dépôt IA lui-même.

## Installation OpenClaw/OpenRouter

Pour installer, configurer, mettre à jour ou diagnostiquer OpenClaw/OpenRouter, utiliser exclusivement la documentation et les points d'entrée de :

```text
mathiasseguincadiche/openclaw_openrouter
```

Ce dépôt Windows ne recopiera pas ces procédures afin d'éviter la dérive documentaire et la duplication de responsabilités.

## Critère de conformité

La frontière est respectée lorsque `Windows_11_Pro_Custom` peut être installé, audité, vérifié, sauvegardé et restauré **sans dépendre de la présence d'OpenClaw/OpenRouter**.

Inversement, l'état d'OpenClaw/OpenRouter ne fait pas partie du verdict de conformité de la workstation.
