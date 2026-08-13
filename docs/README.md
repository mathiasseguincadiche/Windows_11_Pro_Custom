# Documentation officielle — Windows 11 Pro Custom

Ce dossier contient la **documentation technique officielle** de `Windows_11_Pro_Custom`.

Le [`README.md`](../README.md) racine est la vitrine du projet. Ici, l'objectif est différent : documenter **comment comprendre, réaliser, exploiter, valider, maintenir et récupérer la workstation** sans devoir lire le dépôt au hasard.

> La documentation active décrit l'état actuel. L'historique appartient à [`CHANGELOG.md`](../CHANGELOG.md) et à Git.

## Choisir le bon parcours

| Objectif | Parcours recommandé |
| --- | --- |
| Découvrir le projet | [`../README.md`](../README.md) → [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) |
| Réaliser le projet de A à Z | [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) |
| Installer Windows depuis zéro | [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) → [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) |
| Comprendre l'orchestration | [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) |
| Trouver une commande | [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) |
| Vérifier la conformité | [`11_VALIDATION.md`](11_VALIDATION.md) → [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md) |
| Diagnostiquer un problème | [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) |
| Savoir quel fichier fait autorité | [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md) |
| Apprendre WSL2 | [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md) → [`06_WSL2.md`](06_WSL2.md) |
| Reconstruire après incident | [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) → [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) |
| Intégrer OpenClaw/OpenRouter | [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md) |

Le **parcours opérationnel principal** est `20_RUNBOOK_OPERATIONNEL.md`. Le Runbook de réinstallation `13` est réservé à la reprise après incident et ne remplace pas la procédure normale de réalisation du projet.

---

## Carte de la documentation

### Comprendre la workstation

| Document | Responsabilité |
| --- | --- |
| [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) | Architecture globale, frontières Windows/WSL2, stockage, dépôt et sources de vérité |
| [`03_STOCKAGE.md`](03_STOCKAGE.md) | Rôle de `C:`, `D:`, VHDX WSL2, ext4 et placement des données |
| [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md) | Hiérarchie entre état réel, contrats, scripts, rapports et documentation |

### Construire la machine

| Document | Responsabilité |
| --- | --- |
| [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) | Préparer une base Windows 11 Pro depuis zéro |
| [`02_BIOS_DRIVERS.md`](02_BIOS_DRIVERS.md) | UEFI, Secure Boot, TPM, virtualisation, ReBAR et stratégie de pilotes |
| [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) | Réaliser le projet : audit → plan → convergence → validation → idempotence → sauvegarde |

### Windows, sécurité et usages desktop

| Document | Responsabilité |
| --- | --- |
| [`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md) | Profils Windows, mesures, limites et rollback |
| [`05_DEFENDER_PERFORMANCE.md`](05_DEFENDER_PERFORMANCE.md) | Defender et politique d'exclusions deny-by-default |
| [`08_APPLICATIONS.md`](08_APPLICATIONS.md) | Catalogue applicatif et stratégie WinGet |
| [`09_GAMING_OLED.md`](09_GAMING_OLED.md) | Gaming et affichage sans mélanger cette couche avec le backend DevOps |

### WSL2 et DevOps

| Document | Responsabilité |
| --- | --- |
| [`06_WSL2.md`](06_WSL2.md) | Contrat réel WSL2 de la workstation |
| [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md) | Docker, Kubernetes, Terraform, Ansible, AWS, GitHub CLI et outils qualité |
| [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md) | Guide pédagogique Linux/WSL2 pour débuter et comprendre les commandes |

### Orchestration, exploitation et maintenance

| Document | Responsabilité |
| --- | --- |
| [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) | Machine-first, plan, idempotence, Apply ciblé, re-Verify et logs |
| [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md) | Windows Update, WinGet, WSL, Ubuntu, DevOps épinglé et VS Code |
| [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md) | `START_MENU.cmd` / `menu.ps1` et routage vers les orchestrateurs |
| [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) | Référence des paramètres de `install.ps1`, `update.ps1` et commandes associées |
| [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) | Diagnostic par symptôme et méthode de résolution |

### Validation et qualification

| Document | Responsabilité |
| --- | --- |
| [`11_VALIDATION.md`](11_VALIDATION.md) | Comment produire une preuve de conformité réelle |
| [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md) | Contrôles matériels automatiques et preuves manuelles |
| [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md) | Checklist officielle pour déclarer le projet terminé |

### Sauvegarde et reprise

| Document | Responsabilité |
| --- | --- |
| [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) | Politique de sauvegarde et validation des backups |
| [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) | Reconstruction après panne, remplacement de disque ou réinstallation |

### Intégrations optionnelles

| Document | Responsabilité |
| --- | --- |
| [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md) | Intégration Windows-native d'OpenClaw/OpenRouter et frontière avec WSL2 |

---

## Les quatre documents opérationnels à connaître

Pour travailler réellement sur la machine, quatre documents couvrent la majorité des besoins :

1. [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) — **quoi faire et dans quel ordre** ;
2. [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) — **quelle commande et quel paramètre utiliser** ;
3. [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) — **quoi vérifier lorsqu'une étape échoue** ;
4. [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md) — **comment savoir que le projet est terminé**.

`11_VALIDATION.md`, `14_ORCHESTRATION.md` et `23_SOURCES_DE_VERITE.md` expliquent les mécanismes derrière ces opérations.

---

## Règles documentaires

La documentation officielle suit ces règles :

- **un document = une responsabilité principale** ;
- le README explique le projet sans recopier toute la documentation ;
- le Runbook opérationnel donne l'ordre des opérations sans devenir une encyclopédie ;
- la référence de commandes documente les interfaces réelles du code ;
- le troubleshooting explique le diagnostic, pas une succession de contournements ;
- l'historique de versions n'est pas mélangé à la documentation active ;
- un ancien nom technique reste mentionné uniquement s'il existe encore réellement dans le code ou dans un contrat ;
- en cas de divergence, la documentation doit être corrigée pour refléter l'implémentation et les contrats actuels.

La hiérarchie détaillée des sources de vérité est définie dans [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

---

## Point de départ recommandé

Pour une machine existante :

```powershell
.\install.ps1 -Mode Audit
```

Pour voir ce que la convergence complète ferait sans modifier la machine :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Ensuite, suivre [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) jusqu'à la validation et à la sauvegarde de référence.