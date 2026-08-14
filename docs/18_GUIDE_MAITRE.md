# Guide maître — vue consolidée du projet

Ce document donne **une vue consolidée** de `Windows_11_Pro_Custom` et oriente vers le guide qui fait référence pour chaque sujet.

Il n'a pas vocation à recopier tous les détails techniques. Pour réaliser le projet dans le bon ordre, utiliser [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).

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
audit et convergence
   ↓
validation
   ↓
idempotence
   ↓
maintenance et sauvegarde
```

Le principe central est celui d'une **workstation-as-code** : l'état réel est observé, comparé aux contrats actuels, corrigé uniquement lorsque nécessaire puis re-vérifié.

---

## Répartition des responsabilités

```text
Windows
├── desktop
├── sécurité
├── pilotes
├── PowerShell
├── VS Code
├── WezTerm
└── runtime WSL

Ubuntu WSL2
├── Bash / Git
├── Docker
├── Kubernetes
├── Terraform / Ansible
└── AWS / GitHub CLI

WezTerm
├── Ubuntu DevOps (WSL2) <- défaut
└── PowerShell 7         <- Windows

Orchestration
├── install.ps1
├── update.ps1
└── menu.ps1

Preuves
├── logs\
└── reports\
```

Les projets Linux actifs restent sur le filesystem ext4 de WSL2, sous `~/projects`, `~/labs` ou `~/repositories`.

Les projets externes, notamment OpenClaw/OpenRouter, restent indépendants de l'orchestrateur de la workstation.

---

## Les parcours à distinguer

### Installation initiale

Commence par [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md), puis suis le Runbook opérationnel.

### Utilisation quotidienne

```text
menu.ps1 / install.ps1 / update.ps1
```

### Reconstruction après incident

Utilise [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md).

Ne mélange pas le parcours quotidien et la reprise bare-metal.

---

## Cycle opérationnel normal

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

Une exécution réussie d'`Apply` ne suffit pas à elle seule : la conformité vient de l'état réellement observé et des validateurs.

---

## Où trouver le détail

| Sujet | Référence |
| --- | --- |
| Architecture et frontières | [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) |
| Installation Windows | [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) |
| BIOS / pilotes | [`02_BIOS_DRIVERS.md`](02_BIOS_DRIVERS.md) |
| Stockage | [`03_STOCKAGE.md`](03_STOCKAGE.md) |
| Optimisation Windows | [`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md) |
| Defender / performance | [`05_DEFENDER_PERFORMANCE.md`](05_DEFENDER_PERFORMANCE.md) |
| WSL2 | [`06_WSL2.md`](06_WSL2.md) |
| Stack DevOps / terminal | [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md) |
| Applications | [`08_APPLICATIONS.md`](08_APPLICATIONS.md) |
| Gaming / OLED | [`09_GAMING_OLED.md`](09_GAMING_OLED.md) |
| Backup / restore | [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) |
| Validation | [`11_VALIDATION.md`](11_VALIDATION.md) |
| Matériel | [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md) |
| Reconstruction | [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) |
| Orchestration | [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) |
| Mises à jour | [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md) |
| Guide WSL2 pédagogique | [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md) |
| Centre de contrôle | [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md) |
| Frontière OpenClaw/OpenRouter | [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md) |
| Réalisation de bout en bout | [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) |
| Référence des commandes | [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) |
| Troubleshooting | [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) |
| Sources de vérité | [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md) |
| Critères d'acceptation | [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md) |

---

## Séquence recommandée depuis une machine propre

```text
Windows sain
→ pilotes essentiels
→ audit
→ plan
→ applications / réglages
→ WSL2
→ stack DevOps
→ terminal / VS Code
→ qualification matériel
→ validation globale
→ idempotence
→ sauvegarde de référence
```

Le détail de chaque étape reste volontairement dans le document spécialisé correspondant.

---

## Frontière avec OpenClaw/OpenRouter

OpenClaw/OpenRouter peut être utilisé sur la même machine, mais `Windows_11_Pro_Custom` ne l'installe pas, ne le configure pas, ne le déclenche pas et ne le valide pas.

Le dépôt `mathiasseguincadiche/openclaw_openrouter` possède intégralement cette plateforme IA. Le document [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md) existe uniquement pour empêcher une dérive de responsabilité entre les deux projets.

---

## Comment choisir le bon document

```text
Question sur le fonctionnement global ?
→ README.md / 00_ARCHITECTURE.md

Question « comment faire le projet ? »
→ 20_RUNBOOK_OPERATIONNEL.md

Question sur une commande ?
→ 21_REFERENCE_COMMANDES.md

Question sur un échec ?
→ 22_TROUBLESHOOTING.md

Question « quel fichier fait autorité ? »
→ 23_SOURCES_DE_VERITE.md

Question « est-ce terminé ? »
→ 24_CRITERES_ACCEPTATION.md

Question OpenClaw/OpenRouter ?
→ dépôt openclaw_openrouter ; doc 19 uniquement pour la frontière
```

---

## Résultat final recherché

```text
workstation stable
+
Windows compréhensible
+
WSL2 conforme
+
DevOps qualifié
+
terminal cohérent
+
matériel qualifié
+
maintenance maîtrisée
+
reprise documentée
+
preuves exploitables
```

La documentation active décrit cet état présent. L'historique reste dans `CHANGELOG.md` et Git.
