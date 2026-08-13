# Documentation officielle — Windows 11 Pro Custom

Ce dossier contient la **documentation technique officielle** de `Windows_11_Pro_Custom`.

Le [`README.md`](../README.md) racine présente le projet. Ici, la documentation explique comment **comprendre l'architecture, réaliser la workstation, utiliser ses environnements, la valider, la maintenir et la récupérer**.

> La documentation active décrit l'état actuel. L'historique appartient à [`CHANGELOG.md`](../CHANGELOG.md) et à Git.

## Choisir le bon parcours

| Objectif | Parcours recommandé |
| --- | --- |
| Découvrir le projet | [`../README.md`](../README.md) → [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) → [`18_GUIDE_MAITRE.md`](18_GUIDE_MAITRE.md) |
| Réaliser le projet de A à Z | [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) |
| Installer Windows depuis zéro | [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) → [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) |
| Comprendre WSL2 | [`06_WSL2.md`](06_WSL2.md) ; version pédagogique : [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md) |
| Utiliser la stack DevOps et WezTerm | [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md) |
| Utiliser OpenClaw/clawops depuis Windows/WezTerm | [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md) |
| Comprendre l'orchestration | [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) |
| Trouver une commande | [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) |
| Vérifier la conformité | [`11_VALIDATION.md`](11_VALIDATION.md) → [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md) |
| Diagnostiquer un problème | [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) |
| Savoir quel fichier fait autorité | [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md) |
| Reconstruire après incident | [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) → [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) |

Le parcours quotidien et la reconstruction après incident sont volontairement séparés. Le **Runbook opérationnel `20`** décrit la réalisation et la convergence normales ; le **Runbook `13`** concerne la reprise.

---

## Carte de la documentation

### Architecture et état attendu

| Document | Responsabilité |
| --- | --- |
| [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) | Répartition Windows / WSL2 / WezTerm / OpenClaw et stockage |
| [`18_GUIDE_MAITRE.md`](18_GUIDE_MAITRE.md) | Vue consolidée courte et orientation vers les références |
| [`03_STOCKAGE.md`](03_STOCKAGE.md) | Rôle de `C:`, `D:`, VHDX WSL2, ext4 et placement des données |
| [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md) | Hiérarchie entre état réel, contrats, scripts, rapports et documentation |

### Construction de la workstation

| Document | Responsabilité |
| --- | --- |
| [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) | Préparer une base Windows 11 Pro |
| [`02_BIOS_DRIVERS.md`](02_BIOS_DRIVERS.md) | Firmware, prérequis matériels et stratégie de pilotes |
| [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) | Audit → plan → convergence → validation → idempotence → sauvegarde |

### Windows et usages desktop

| Document | Responsabilité |
| --- | --- |
| [`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md) | Profils Windows, mesures et réversibilité |
| [`05_DEFENDER_PERFORMANCE.md`](05_DEFENDER_PERFORMANCE.md) | Politique Defender et performance |
| [`08_APPLICATIONS.md`](08_APPLICATIONS.md) | Catalogue applicatif et stratégie WinGet |
| [`09_GAMING_OLED.md`](09_GAMING_OLED.md) | Gaming et affichage sans mélanger cette couche avec le backend DevOps |

### Linux, DevOps et expérience terminal

| Document | Responsabilité |
| --- | --- |
| [`06_WSL2.md`](06_WSL2.md) | Contrat WSL2 réel de la workstation |
| [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md) | Stack DevOps, profils WezTerm, shell Linux et VS Code/WSL |
| [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md) | Guide pédagogique Linux/WSL2 pour débuter et comprendre les commandes |

WezTerm est traité ici comme **interface de contextes** : Ubuntu DevOps reste le profil par défaut, PowerShell 7 le contexte Windows général et `OpenClaw / clawops (Windows)` le contexte CLI IA Windows-native.

### OpenClaw/OpenRouter

| Document | Responsabilité |
| --- | --- |
| [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md) | Installation/validation de l'intégration Windows, accès CLI WezTerm et frontière avec WSL2 |

Ce guide reste centré sur **l'intégration à la workstation**. Les fonctions métier OpenClaw, les agents, modèles et opérations propres au control-plane restent documentés dans `openclaw_openrouter`.

### Orchestration, exploitation et maintenance

| Document | Responsabilité |
| --- | --- |
| [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) | Machine-first, plan, Apply ciblé, re-Verify, idempotence et preuves |
| [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md) | Windows Update, WinGet, WSL, Ubuntu, DevOps et VS Code |
| [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md) | `START_MENU.cmd` / `menu.ps1` et routage vers les orchestrateurs |
| [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) | Paramètres publics de `install.ps1`, `update.ps1` et commandes associées |
| [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) | Diagnostic par domaine, y compris WezTerm et OpenClaw |

### Validation et qualification

| Document | Responsabilité |
| --- | --- |
| [`11_VALIDATION.md`](11_VALIDATION.md) | Produire une preuve de conformité réelle |
| [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md) | Contrôles matériels automatiques et preuves manuelles |
| [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md) | Checklist officielle pour déclarer le projet terminé |

### Sauvegarde et reprise

| Document | Responsabilité |
| --- | --- |
| [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) | Politique de sauvegarde et validation des backups |
| [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) | Reconstruction après incident ou réinstallation |

---

## Les documents opérationnels à connaître

1. [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) — **quoi faire et dans quel ordre** ;
2. [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) — **quelle interface utiliser** ;
3. [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) — **comment diagnostiquer un écart** ;
4. [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md) — **comment savoir que le projet est terminé**.

Pour comprendre les mécanismes derrière ces opérations : [`11_VALIDATION.md`](11_VALIDATION.md), [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) et [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

---

## Règles documentaires

- **un document = une responsabilité principale** ;
- le README présente le projet sans recopier les guides spécialisés ;
- `00_ARCHITECTURE.md` décrit les frontières, pas les procédures détaillées ;
- `07_DEVOPS_STACK.md` possède l'expérience terminal et DevOps ;
- `19_OPENCLAW_OPENROUTER_WINDOWS.md` possède l'intégration OpenClaw Windows, pas la documentation fonctionnelle du produit IA ;
- le Runbook `20` donne l'ordre d'exécution ;
- le Runbook `13` reste réservé à la reprise ;
- le troubleshooting explique le diagnostic plutôt qu'une collection de contournements ;
- `CHANGELOG.md` et Git conservent l'historique ;
- en cas de divergence, la documentation active est corrigée pour refléter les contrats et l'implémentation actuels.

Voir [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

---

## Point de départ recommandé

```powershell
.\install.ps1 -Mode Audit
```

Puis calculer le plan correspondant au périmètre souhaité avant toute convergence. Le détail, y compris la différence entre workstation core et `-FullInstall`, est dans [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).