# Documentation officielle — Windows 11 Pro Custom

Ce dossier contient la documentation active de `Windows_11_Pro_Custom`.

La règle éditoriale est simple : **chaque document doit répondre à un besoin principal**. Un README présente, un guide enseigne, une référence donne des valeurs exactes et un runbook décrit une procédure opérationnelle. Cette séparation évite de répéter les mêmes informations dans plusieurs fichiers et réduit le risque de divergence avec le code.

> La documentation active décrit l'état actuel. L'historique appartient à [`CHANGELOG.md`](../CHANGELOG.md) et à Git.

## Choisir le bon document

| Votre besoin | Document à ouvrir |
| --- | --- |
| Comprendre ce qu'est le projet | [`../README.md`](../README.md) |
| Découvrir les concepts avant d'exécuter | [`18_GUIDE_MAITRE.md`](18_GUIDE_MAITRE.md) |
| Trouver un terme inconnu | [`GLOSSAIRE.md`](GLOSSAIRE.md) |
| Comprendre l'architecture Windows / WSL2 | [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) |
| Installer Windows depuis zéro | [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) |
| Exécuter le parcours normal de A à Z | [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) |
| Trouver une commande ou un paramètre exact | [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) |
| Diagnostiquer un problème | [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) |
| Savoir quelle source fait foi | [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md) |
| Décider si la workstation est réellement prête | [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md) |
| Sécuriser l'identité de `C:` et `E:` | [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md) |
| Comprendre preuves, drift et restauration | [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md) |
| Reconstruire après incident | [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) |

## Parcours recommandé pour un débutant

```text
README.md
   ↓
18_GUIDE_MAITRE.md
   ↓
GLOSSAIRE.md si nécessaire
   ↓
00_ARCHITECTURE.md
   ↓
01_INSTALLATION_WINDOWS.md si Windows doit être installé
   ↓
20_RUNBOOK_OPERATIONNEL.md
   ↓
24_CRITERES_ACCEPTATION.md
```

Le but n'est pas de lire tous les fichiers avant d'agir. Le portail sert à ouvrir **le bon niveau d'information au bon moment**.

## Rôle de chaque type de documentation

### 1. Porte d'entrée

- [`../README.md`](../README.md) — explique **quoi**, **pour qui**, **pourquoi** et **par où commencer** ;
- [`18_GUIDE_MAITRE.md`](18_GUIDE_MAITRE.md) — explique les concepts structurants sans remplacer les références techniques ;
- [`GLOSSAIRE.md`](GLOSSAIRE.md) — définit le vocabulaire utilisé dans le projet.

### 2. Architecture et contrats techniques

- [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) — frontières Windows / WSL2 / Windows Terminal / VS Code ;
- [`02_BIOS_DRIVERS.md`](02_BIOS_DRIVERS.md) — firmware et pilotes ;
- [`03_STOCKAGE.md`](03_STOCKAGE.md) — contrat `C:`, `E:`, VHDX WSL2 et ext4 ;
- [`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md) — politique d'optimisation ;
- [`05_DEFENDER_PERFORMANCE.md`](05_DEFENDER_PERFORMANCE.md) — politique Defender ;
- [`06_WSL2.md`](06_WSL2.md) — contrat WSL2 ;
- [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md) — stack DevOps, Windows Terminal et expérience terminal ;
- [`08_APPLICATIONS.md`](08_APPLICATIONS.md) — catalogue applicatif ;
- [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) — architecture de sauvegarde et restauration ;
- [`11_VALIDATION.md`](11_VALIDATION.md) — modèle de validation ;
- [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md) — qualification matérielle ;
- [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) — fonctionnement machine-first de l'orchestrateur ;
- [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md) — politique de maintenance ;
- [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md) — frontière avec le projet IA externe.

### 3. Guides pédagogiques et scénarios d'usage

- [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) — installation initiale Windows ;
- [`09_GAMING_OLED.md`](09_GAMING_OLED.md) — usage gaming/OLED optionnel ;
- [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md) — apprentissage WSL2 pour lecteur débutant ;
- [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md) — utilisation du centre de contrôle.

### 4. Runbooks

Un runbook répond à : **« je dois effectuer l'opération maintenant ; dans quel ordre, avec quels contrôles et quelles conditions d'arrêt ? »**

- [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) — convergence et qualification normales ;
- [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) — incident majeur, restauration ou reconstruction.

### 5. Références et décision

- [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) — interfaces publiques et commandes ;
- [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) — diagnostic par symptôme ;
- [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md) — hiérarchie de confiance ;
- [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md) — Definition of Done de la workstation ;
- [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md) — identité physique du stockage ;
- [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md) — preuves `STATIC`, `SIMULATED`, `PHYSICAL`, drift et drill de restauration.

## Règles de lecture

### Une valeur exacte

Pour une version, un chemin, un profil ou une application, commencez par la source de vérité déclarative indiquée dans [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

La documentation explique le contrat ; elle ne doit pas inventer un second contrat indépendant.

### Une opération à exécuter

Utilisez un runbook. Chaque étape doit préciser :

```text
objectif
→ prérequis
→ commande
→ résultat attendu
→ preuve / contrôle
→ condition d'arrêt
→ étape suivante
```

### Un problème

Utilisez [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) :

```text
symptôme
→ impact
→ diagnostic non destructif
→ cause probable
→ correction
→ vérification
→ escalade / STOP
```

### Une divergence documentaire

Ne corrigez pas le code pour « faire correspondre la documentation » sans vérifier le contrat. Utilisez l'ordre d'arbitrage de [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

## Premier parcours opérationnel

Commencez toujours par l'observation :

```powershell
.\install.ps1 -Mode Audit
```

Lors d'une première qualification, l'identité physique du stockage V25 doit être enrôlée après contrôle humain :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Audit
.\scripts\bootstrap\00_storage_identity_v25.ps1 `
  -Mode Record `
  -ConfirmHealthyTopology
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Verify
```

Si la baseline existe déjà, n'exécutez pas `Record` : vérifiez-la.

Ensuite :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Ordre complet : [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).

## Frontière OpenClaw/OpenRouter

OpenClaw/OpenRouter est un projet externe. `Windows_11_Pro_Custom` construit la workstation ; il ne possède ni le runtime IA ni son installation. La frontière normative se trouve dans [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

## Convention éditoriale

La documentation utilise un français professionnel accessible :

- expliquer un terme avant de s'appuyer dessus ;
- préciser **quoi**, **pourquoi** et **comment vérifier** lorsqu'une notion est importante ;
- réserver les commandes exactes aux blocs de code ;
- signaler explicitement les opérations destructives ou irréversibles ;
- ne jamais présenter une preuve `SIMULATED` comme une preuve `PHYSICAL` ;
- préférer un lien vers le document propriétaire à une duplication de plusieurs paragraphes ;
- conserver les noms techniques réels des scripts lorsqu'ils sont nécessaires à l'exécution.

La qualité documentaire fait partie du contrat du projet : une fonctionnalité non documentée ou une documentation fausse constitue un défaut à corriger.
