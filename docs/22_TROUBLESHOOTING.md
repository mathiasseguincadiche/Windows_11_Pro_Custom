# Troubleshooting — diagnostiquer la workstation par domaine

Ce guide décrit **comment diagnostiquer un écart sans mélanger les responsabilités du projet**.

Avant toute correction, identifier la source de vérité concernée avec [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

## Méthode générale

```text
1. observer le symptôme
2. identifier le domaine propriétaire
3. lire le log ou le rapport correspondant
4. comparer l'état réel au contrat courant
5. prévisualiser la correction lorsque c'est possible
6. appliquer uniquement le delta compris
7. relancer la même validation
8. vérifier l'absence de régression
```

Un message d'erreur dans un terminal ne signifie pas automatiquement que le terminal est responsable. Il faut distinguer l'interface, le runtime et l'outil réellement en échec.

---

## Où chercher les preuves

### Orchestration

```text
logs\install.log
logs\runs\<RunId>\events.ndjson
logs\runs\<RunId>\summary.json
reports\orchestration\latest-run.json
reports\orchestration\machine-state.json
```

### Mises à jour

```text
logs\updates\system-update.log
reports\updates\latest-run.json
```

### Composants

Les sous-composants peuvent produire leurs propres journaux sous `logs\<catégorie>\` et leurs rapports sous `reports\`.

Un ancien rapport explique une exécution passée ; il ne remplace pas une nouvelle observation de la machine.

---

# Orchestration

## `Audit` fonctionne mais `Verify` échoue

C'est possible :

```text
Audit  -> observe et décrit
Verify -> exige la conformité
```

Procédure :

1. identifier le composant en échec ;
2. lire son contrat ;
3. comparer avec l'état réel ;
4. lancer un `Apply` ciblé si le delta est compris ;
5. relancer `Verify`.

## Le même composant revient toujours dans le plan

Symptôme : après convergence, `PlanOnly` repropose le même changement.

Vérifier :

- que `Verify` teste bien l'état produit par `Apply` ;
- que le fichier ou réglage généré est stable ;
- qu'une étape externe ne modifie pas l'état après convergence ;
- qu'une nouvelle session ou un redémarrage de composant n'est pas explicitement requis.

Comparer le probe, l'application et le post-verify du même `RunId`.

---

# WSL2

## WSL n'est pas disponible

Commencer par :

```powershell
wsl --status
wsl --version
```

Puis suivre [`06_WSL2.md`](06_WSL2.md) et relancer la validation ciblée :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

## Ubuntu existe mais l'emplacement ne correspond pas

Le contrat courant attend :

```text
D:\WSL\Ubuntu-DevOps
```

Ne considérer la distribution conforme que lorsque son emplacement et sa release sont prouvés par le validateur.

Si une migration ou une reconstruction devient nécessaire, utiliser les procédures dédiées au lieu de transformer un simple `Verify` en opération de reprise.

## Mauvaise release Ubuntu

Le contrat attend Ubuntu 26.04 / `resolute`.

Une release différente doit être traitée comme un écart de contrat, pas comme une simple différence cosmétique.

## `.wslconfig` ne correspond pas au profil

Vérifier le profil demandé et `%USERPROFILE%\.wslconfig`, puis utiliser le parcours normal de convergence du projet.

Guide complet : [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md).

---

# Stack DevOps

## Certains outils sont absents ou à la mauvaise version

La source de vérité est :

```text
config/devops/tool-versions.env
```

Utiliser la convergence du projet :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

puis :

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

## Docker fonctionne mais la validation DevOps échoue

Docker n'est qu'un élément de la qualification. Vérifier également :

- Compose et Buildx ;
- service Docker ;
- kubectl / Helm ;
- Terraform / Ansible ;
- AWS CLI / GitHub CLI ;
- outils qualité ;
- HOME Linux et racines de travail.

Guide : [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md).

---

# WezTerm et expérience terminal

## La configuration WezTerm n'est pas conforme

La source de vérité est :

```text
config/wezterm/wezterm.lua
```

Le contrat attendu contient :

```text
Ubuntu DevOps (WSL2)          <- défaut
PowerShell 7
OpenClaw / clawops (Windows)
```

Validation générale :

```powershell
.\install.ps1 -Mode Verify
```

Si `%USERPROFILE%\.wezterm.lua` diffère de la configuration versionnée, utiliser le parcours normal `Audit` / `Apply` / `Verify` plutôt que de modifier manuellement plusieurs copies.

## Le mauvais profil est utilisé

Utiliser :

```text
Ubuntu DevOps (WSL2) -> commandes et projets Linux
PowerShell 7         -> administration Windows
OpenClaw / clawops   -> CLI IA Windows-native
```

Le fait qu'une commande soit disponible depuis WezTerm ne change pas son runtime réel.

## `OpenClaw / clawops (Windows)` indique une CLI absente

Séparer le diagnostic :

### 1. Vérifier WezTerm

```powershell
.\install.ps1 -Mode Verify
```

Cette étape prouve que le profil terminal attendu est bien déployé.

### 2. Vérifier OpenClaw

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

Cette étape prouve que le runtime et les launchers existent réellement.

### 3. Ouvrir une nouvelle session du profil

Le profil relit lui-même les variables utilisateur OpenClaw et complète son `PATH` de session avec les emplacements gérés. Une relance complète de WezTerm n'est pas requise uniquement pour rafraîchir ces valeurs.

Smoke test :

```powershell
openclaw --version
clawops version
clawops platform check
```

Si `Verify` WezTerm réussit mais `ValidateOpenClawAI` échoue, le problème appartient à l'intégration OpenClaw, pas au terminal.

---

# VS Code

## Un projet WSL est ouvert comme un dossier Windows

Pour un projet Linux, vérifier que VS Code est relié à la distribution WSL et que le chemin actif est sous `/home/<user>/...`.

L'objectif est que le terminal intégré, les extensions et les outils du projet utilisent le même environnement Linux.

---

# OpenClaw/OpenRouter

## Le control-plane ne correspond pas à la cible

La source de vérité côté workstation est :

```text
config/openclaw/control-plane.json
```

La version et les contrats fonctionnels détaillés restent possédés par `openclaw_openrouter`.

Une modification du control-plane doit être qualifiée dans son dépôt avant mise à jour volontaire du pin Windows.

## Le checkout local contient des changements

Commencer par comprendre ces changements avant toute synchronisation. Le dépôt Windows ne doit pas traiter un état local inconnu comme s'il était jetable.

## OpenClaw fonctionne dans PowerShell mais pas dans le profil WezTerm

Vérifier dans cet ordre :

1. `install.ps1 -Mode Verify` pour la configuration terminal ;
2. `-ValidateOpenClawAI` pour le runtime ;
3. le diagnostic affiché à l'ouverture du profil ;
4. les chemins `D:\AI\OpenClaw\npm-global` et `D:\AI\OpenClaw\venv\Scripts` ;
5. les variables utilisateur OpenClaw attendues.

Guide : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

# Matériel et stockage

## Qualification bloquée sur `ACTION REQUISE`

Certaines preuves restent humaines lorsqu'elles ne peuvent pas être observées de manière fiable depuis Windows.

Compléter les preuves demandées puis relancer :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

## `D:` ou le stockage attendu ne correspond pas

Vérifier la lettre du volume, le filesystem, l'espace disponible et les chemins réellement observés avant de poursuivre.

Guide : [`03_STOCKAGE.md`](03_STOCKAGE.md).

---

# Maintenance

## Une mise à jour est partiellement réussie

`update.ps1` traite plusieurs catégories indépendantes.

Lire :

```text
reports\updates\latest-run.json
```

puis revalider uniquement les domaines concernés.

Guide : [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

# Sauvegarde

## La sauvegarde n'est pas validée

Vérifier :

- le support attendu ;
- sa capacité ;
- la présence des données nécessaires ;
- l'export WSL prévu ;
- les rapports de validation du composant backup.

Une sauvegarde non vérifiée ne compte pas comme critère d'acceptation rempli.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

# CI GitHub

## Le workflow `Documentation` échoue

Il vérifie notamment :

- la présence des documents canoniques ;
- la cohérence de l'identité et des parcours ;
- les contrats documentés ;
- les paramètres publics ;
- les liens Markdown locaux ;
- l'absence de documentation active fondée sur d'anciennes versions.

Corriger la divergence documentaire ou le contrat réellement devenu obsolète ; ne supprimer le contrôle que si sa responsabilité n'existe plus.

## `quality` ou `DevOps terminal` échoue

Identifier le job exact : PowerShell, Bash, configuration structurée, Lua WezTerm, actionlint, contrat terminal ou autre contrôle ciblé.

Un échec CI du dépôt et un échec de qualification de la machine sont deux niveaux différents. Les deux doivent rester cohérents, mais ils ne se remplacent pas.

---

## Quand utiliser le Runbook de reconstruction

Tant que la workstation existe et qu'un composant est simplement incohérent, utiliser le parcours normal :

```text
Audit -> Plan -> Apply ciblé -> Verify
```

Utiliser [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) lorsque le besoin est réellement une reconstruction ou une reprise complète.

Le Runbook quotidien reste [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).