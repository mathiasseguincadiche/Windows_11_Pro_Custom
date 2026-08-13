# Guide maître — vue consolidée du projet

Ce document n'est plus une encyclopédie du dépôt. Son rôle est de donner **une vue unique du projet et d'orienter vers le document qui fait réellement référence pour chaque sujet**.

Pour découvrir le projet, lire d'abord le [`README.md`](../README.md). Pour le réaliser, suivre [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).

## Le projet en une chaîne

```text
matériel réel
   ↓
Windows 11 Pro
   ↓
configuration versionnée
   ↓
WSL2 Ubuntu / stack DevOps
   ↓
audit et convergence
   ↓
validation
   ↓
idempotence
   ↓
maintenance et sauvegarde
```

Le principe central est celui d'une **workstation-as-code** : l'état réel est observé, comparé aux contrats actuels, corrigé uniquement lorsque nécessaire puis re-vérifié.

## Responsabilités

```text
Windows
└── desktop / pilotes / sécurité / PowerShell / VS Code / WSL runtime

WSL2 Ubuntu
└── Bash / Git / Docker / Kubernetes / Terraform / Ansible / AWS

Orchestration
└── install.ps1 / update.ps1 / menu.ps1

Preuves
└── logs / reports / validateurs

Recovery
└── sauvegarde Windows + export WSL + runbook de reprise
```

Les projets Linux actifs restent sur le filesystem ext4 de WSL2, sous `~/projects`, `~/labs` ou `~/repositories`.

## Cycle opérationnel

```text
Audit
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

Une exécution réussie d'`Apply` ne suffit pas : la conformité vient de l'état réellement observé et des validateurs.

## Où trouver le détail

| Sujet | Référence |
| --- | --- |
| Architecture | [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) |
| Installation Windows | [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) |
| Stockage | [`03_STOCKAGE.md`](03_STOCKAGE.md) |
| WSL2 | [`06_WSL2.md`](06_WSL2.md) |
| Stack DevOps | [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md) |
| Backup / restore | [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) |
| Validation | [`11_VALIDATION.md`](11_VALIDATION.md) |
| Matériel | [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md) |
| Orchestration | [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) |
| Mises à jour | [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md) |
| Centre de contrôle | [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md) |
| OpenClaw/OpenRouter | [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md) |
| Réalisation A à Z | [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) |
| Commandes | [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) |
| Dépannage | [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) |
| Sources de vérité | [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md) |
| Critères d'acceptation | [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md) |

## Règle de lecture

Ne chercher le détail ici que pour comprendre **comment les grandes briques s'enchaînent**. Les valeurs, commandes, procédures et critères précis appartiennent aux guides spécialisés afin d'éviter les copies divergentes.

La documentation active décrit l'état courant ; `CHANGELOG.md` et Git conservent l'historique.