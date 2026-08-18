# Guide maître — vue consolidée du projet

Ce document donne **une vue consolidée** de `Windows_11_Pro_Custom` et oriente vers les guides qui font référence. Pour réaliser le projet dans le bon ordre, suivre [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).

## Le projet en une chaîne

```text
matériel réel
   ↓
Windows 11 Pro
   ↓
configuration versionnée
   ↓
WezTerm / VS Code
   ├── Ubuntu DevOps (WSL2) -> Linux DevOps
   └── PowerShell 7         -> Windows
   ↓
audit → plan → convergence → validation
   ↓
idempotence → maintenance → sauvegarde
```

Le principe central est **workstation-as-code** : l'état réel est observé, comparé aux contrats actuels, corrigé uniquement lorsque nécessaire puis re-vérifié.

## Responsabilités

```text
Windows
└── desktop / pilotes / sécurité / PowerShell / VS Code / WezTerm / runtime WSL

WSL2 Ubuntu
└── Bash / Git / Docker / Kubernetes / Terraform / Ansible / AWS

WezTerm
├── Ubuntu DevOps (WSL2) <- défaut
└── PowerShell 7         <- Windows

Orchestration
└── install.ps1 / update.ps1 / menu.ps1

Preuves
└── logs / reports
```

Les projets Linux actifs restent sur le filesystem ext4 de WSL2 sous `~/projects`, `~/labs` ou `~/repositories`.

## Cycle opérationnel

```text
Audit
  ↓
Contrôle humain C: / E:
  ↓
V25 Record (premier enrôlement uniquement)
  ↓
V25 Verify
  ↓
PlanOnly
  ↓
Apply
  ↓
Verify
  ↓
PlanOnly de contrôle
  ↓
Sauvegarde vérifiée
```

Si la baseline V25 existe déjà et correspond à la topologie physique, seul
`V25 Verify` est rejoué avant les parcours stricts.

Une exécution réussie d'`Apply` ne suffit pas : la conformité vient de l'état réellement observé et des validateurs.

## Où trouver le détail

| Sujet | Référence |
| --- | --- |
| Architecture et frontières | [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) |
| Installation Windows | [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) |
| Stockage | [`03_STOCKAGE.md`](03_STOCKAGE.md) |
| Identité physique C:/E: et reprise | [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md) |
| WSL2 | [`06_WSL2.md`](06_WSL2.md) |
| Stack DevOps et WezTerm | [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md) |
| Backup / restore | [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) |
| Validation | [`11_VALIDATION.md`](11_VALIDATION.md) |
| Matériel | [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md) |
| Reconstruction | [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) |
| Orchestration | [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) |
| Mises à jour | [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md) |
| Centre de contrôle | [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md) |
| Frontière OpenClaw/OpenRouter | [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md) |
| Réalisation A à Z | [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) |
| Commandes | [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) |
| Dépannage | [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) |
| Sources de vérité | [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md) |
| Critères d'acceptation | [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md) |

## Frontière OpenClaw/OpenRouter

`Windows_11_Pro_Custom` ne prépare, n'installe, ne configure, ne déclenche et ne valide pas OpenClaw/OpenRouter. La plateforme IA appartient entièrement au dépôt `mathiasseguincadiche/openclaw_openrouter`.

Le document `19` existe uniquement pour fixer cette frontière et éviter que les responsabilités des deux projets se mélangent à nouveau.

## Règle de lecture

Le guide maître explique **comment les briques de la workstation s'enchaînent**. Les valeurs, commandes, procédures et critères précis appartiennent aux guides spécialisés.

La documentation active décrit l'état courant ; `CHANGELOG.md` et Git conservent l'historique.
