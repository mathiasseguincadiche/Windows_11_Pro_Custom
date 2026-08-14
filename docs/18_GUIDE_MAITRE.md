# Guide maître — vue consolidée du projet

Ce document donne **une vue consolidée** de `Windows_11_Pro_Custom`. Pour réaliser le projet, suivre [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).

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
audit → convergence → validation → idempotence
↓
maintenance → sauvegarde
```

La workstation suit une approche **workstation-as-code** : l'état réel est observé, comparé aux contrats actuels, corrigé uniquement lorsque nécessaire puis re-vérifié.

## Responsabilités

```text
Windows        -> desktop, pilotes, PowerShell, VS Code, WezTerm, runtime WSL
Ubuntu WSL2    -> Bash, Git, Docker, Kubernetes, Terraform, Ansible, AWS
WezTerm        -> Ubuntu DevOps (WSL2) + PowerShell 7
Orchestration  -> install.ps1 / update.ps1 / menu.ps1
Preuves        -> logs / reports / validateurs
```

Les projets Linux actifs restent sur ext4 dans `~/projects`, `~/labs` ou `~/repositories`.

OpenClaw/OpenRouter est un projet indépendant. `Windows_11_Pro_Custom` ne l'installe pas, ne le configure pas et ne le déclenche pas. Voir [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

## Cycle opérationnel

```text
Audit → PlanOnly → Apply → Verify → PlanOnly de contrôle → sauvegarde vérifiée
```

## Où trouver le détail

| Sujet | Référence |
| --- | --- |
| Architecture | [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) |
| Installation Windows | [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) |
| WSL2 | [`06_WSL2.md`](06_WSL2.md) |
| Stack DevOps et WezTerm | [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md) |
| Backup / restore | [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) |
| Validation | [`11_VALIDATION.md`](11_VALIDATION.md) |
| Matériel | [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md) |
| Orchestration | [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) |
| Mises à jour | [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md) |
| Centre de contrôle | [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md) |
| Frontière OpenClaw/OpenRouter | [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md) |
| Parcours complet | [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) |
| Commandes | [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) |
| Dépannage | [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) |
| Sources de vérité | [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md) |
| Critères d'acceptation | [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md) |

La documentation active décrit l'état courant ; `CHANGELOG.md` et Git conservent l'historique.
