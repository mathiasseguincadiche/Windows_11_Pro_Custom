# Centre de contrôle interactif

Le dépôt fournit une interface interactive pour utiliser la workstation sans mémoriser toutes les commandes PowerShell.

Le menu est une **façade ergonomique** au-dessus des moteurs existants. Il ne possède pas une seconde logique d'installation ou de maintenance : les opérations réelles restent portées par `install.ps1`, `update.ps1` et les scripts spécialisés.

## Runtime PowerShell obligatoire

Le centre de contrôle est désormais **PowerShell 7 only**.

Contrat officiel :

```text
PowerShell : 7.6.5 minimum
Edition    : Core
Architecture: x64
Executable : pwsh.exe
```

`Windows PowerShell 5.1` peut rester installé comme composant Windows, mais le dépôt ne l'utilise jamais comme moteur d'exécution ni comme fallback. `START_MENU.cmd` refuse donc l'absence de `pwsh.exe` au lieu de basculer silencieusement sur `powershell.exe`.

Le contrôle réel est centralisé dans :

```text
config/powershell/runtime.json
scripts/core/powershell-runtime.psm1
```

Le moteur d'orchestration importe également ce contrat : un lancement direct de `install.ps1` ou `update.ps1` ne permet donc pas de contourner la politique du menu.

## Démarrage

Depuis l'Explorateur Windows :

```text
START_MENU.cmd
```

Depuis PowerShell 7 ou Windows Terminal :

```powershell
.\menu.ps1
```

Le bandeau affiche la version réellement utilisée, par exemple :

```text
PowerShell : 7.6.5 | Core | x64 | pwsh.exe
Runtime minimum : 7.6.5
```

## Menu principal

Le contrat actuel expose :

```text
1. Installation complète
2. Installation / réparation des logiciels
3. Mises à jour complètes
4. Sauvegarde
5. Restauration / rollback
6. Audit et diagnostic complet
7. Vérification de conformité
8. Composants spécifiques
9. Journaux et rapports
10. Aide
0. Quitter
```

## Architecture

```text
Utilisateur
   ↓
START_MENU.cmd / menu.ps1
   │
   ├── contrat runtime ────────────► PowerShell 7.6.5+ / Core / x64 / pwsh.exe
   ├── installation / conformité ─► install.ps1
   ├── mises à jour ──────────────► update.ps1
   ├── logiciels WinGet ──────────► scripts/bootstrap/03_apps.ps1
   ├── empreinte workstation ─────► scripts/windows/90_workstation_fingerprint.ps1
   ├── drill restauration ────────► scripts/backup/63_restore_drill.ps1
   └── logs / rapports ───────────► logs\ et reports\
```

Une fonctionnalité importante ne doit pas exister uniquement dans le menu.

## Installation complète

L'option **Installation complète** appelle l'orchestrateur global avec `FullInstall`.

Elle couvre notamment :

- préflight et état réel ;
- applications et réglages Windows gérés ;
- WSL2 ;
- stack DevOps ;
- Windows Terminal / VS Code ;
- validations matériel, WSL et DevOps.

Lors d'un premier parcours strict, la baseline d’identité stockage d'identité physique de `C:` et `E:` doit être enregistrée après contrôle humain puis vérifiée.

Référence : [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md).

Si Windows exige un redémarrage, le menu bloque la convergence, propose le reboot dans le parcours interactif puis attend que l'utilisateur relance la même option. Les étapes déjà conformes doivent rester idempotentes.

## Installation / réparation des logiciels

Cette option agit uniquement sur les applications Windows gérées par WinGet.

Un logiciel déjà conforme ne doit pas être réinstallé uniquement parce que l'option a été sélectionnée.

Si WinGet doit être réparé pendant le bootstrap des fondations, le dépôt utilise `Microsoft.WinGet.Client` et `Repair-WinGetPackageManager` directement depuis PowerShell 7. Aucun sous-processus Windows PowerShell 5.1 n'est requis.

## Points de restauration

Le garde-fou de restauration utilise directement le provider Windows `SystemRestore` via CIM depuis PowerShell 7 :

```text
SystemRestore.Enable
SystemRestore.CreateRestorePoint
```

Le dépôt n'appelle plus `Checkpoint-Computer` via Windows PowerShell 5.1. Le comportement reste fail-closed : si le point de restauration requis ne peut pas être créé ou vérifié, la convergence protégée s'arrête.

## Mises à jour

Le menu route vers `update.ps1` et sa politique de maintenance.

Voir [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

## Sauvegarde

Le sous-menu actuel expose :

```text
1. Créer une nouvelle sauvegarde
2. Vérifier une sauvegarde existante
3. Vérifier la restaurabilité d'une session
```

La présence d'une sauvegarde ne suffit pas : le menu permet également de vérifier sa structure et sa restaurabilité selon les scripts du dépôt.

Le Golden Backup appelle le script de point de restauration **dans le même processus PowerShell 7** ; il ne démarre aucun moteur PowerShell historique.

## Restauration / rollback

Le sous-menu expose :

```text
1. Générer un plan de restauration — aucune écriture
2. Rollback des réglages gérés par le dépôt
3. Drill WSL isolé
```

La restauration complète destructive reste volontairement non automatique.

Voir [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) et [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md).

## Audit et vérification

### Audit

L'audit répond à :

> Quel est l'état réel de la workstation maintenant ?

Il observe sans transformer un ancien succès d'installation en preuve actuelle.

### Vérification de conformité

L'option globale appelle réellement :

```text
ValidateHardware
ValidateWsl
ValidateDevOps
```

La configuration Windows Terminal fait partie de la vérification normale de la workstation.

## Composants spécifiques

Le sous-menu `menu.ps1` expose actuellement **sept actions** :

```text
1. WSL2 + stack DevOps + validation
2. Qualification matérielle guidée
3. Audit empreinte SIMULATED
4. Audit empreinte PHYSICAL
5. Vérifier la dérive PHYSICAL
6. Enregistrer la baseline PHYSICAL
7. Remplacer la baseline PHYSICAL — archive + justification
```

### Pourquoi cette séparation ?

- `SIMULATED` sert aux preuves qui ne prétendent pas représenter la machine physique ;
- `PHYSICAL` exige une confirmation explicite sur la workstation réelle ;
- la vérification de dérive compare l'état présent à la baseline ;
- l'enregistrement d'une baseline ne doit intervenir qu'après validation complète ;
- son remplacement doit être justifié et archivé, jamais utilisé pour masquer une anomalie.

Voir [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md).

Windows Terminal peut également être vérifié directement :

```powershell
.\scripts\windows\31_windows_terminal.ps1 -Mode Verify
```

## Journaux et rapports

Le menu ouvre rapidement :

```text
logs\
reports\
```

Les journaux expliquent les opérations ; les rapports structurés portent les résultats de validation, inventaires et preuves.

Le résumé d'orchestration enregistre aussi le runtime PowerShell utilisé : édition, version, minimum accepté, exécutable et architecture.

Un ancien rapport peut expliquer un incident passé mais ne constitue pas une preuve de conformité actuelle.

## Privilèges et UAC

Le menu ne doit pas fonctionner en administrateur permanent « au cas où ».

Il relaie une élévation UAC uniquement pour les actions qui en ont besoin. Lors de cette élévation, il réutilise explicitement **`pwsh.exe`** ; il ne bascule pas vers un autre moteur.

## Mode de test

Le routage peut être exercé sans mutation :

```powershell
.\menu.ps1 -Choice 1 -DryRun -NoPause -NoClear
```

Exemple ciblé :

```powershell
.\menu.ps1 -Choice 8.3 -DryRun -NoPause -NoClear
```

Le mode `DryRun` vérifie le routage du menu ; il ne prouve pas la conformité de la workstation.

## Frontière OpenClaw/OpenRouter

OpenClaw/OpenRouter n'est pas un composant du centre de contrôle. Son installation, sa configuration et sa validation appartiennent au dépôt `mathiasseguincadiche/openclaw_openrouter`.

## Pour un utilisateur débutant

```text
Je découvre le projet
→ README.md
→ docs/18_GUIDE_MAITRE.md

Je dois installer ou converger
→ docs/20_RUNBOOK_OPERATIONNEL.md

La workstation est déjà connue
→ menu.ps1

Je veux comprendre l'orchestration
→ docs/14_ORCHESTRATION.md

J'ai un problème
→ docs/22_TROUBLESHOOTING.md
```

Le centre de contrôle améliore l'ergonomie. L'identité du projet reste une workstation Windows 11 Pro reproductible, vérifiable et standardisée sur PowerShell 7 moderne.
