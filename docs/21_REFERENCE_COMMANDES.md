# Référence des commandes — points d'entrée officiels

Ce document est la **référence opérationnelle des commandes publiques du projet**. Il complète le Runbook [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) en expliquant ce que fait chaque point d'entrée, quand l'utiliser et quel résultat attendre.

Les scripts internes de `scripts/` ne sont pas tous destinés à être lancés directement. Les trois points d'entrée principaux sont :

```text
menu.ps1     -> interface humaine
install.ps1  -> audit, convergence, validation, rollback et backup
update.ps1   -> maintenance multi-couches
```

---

## 1. `menu.ps1` — centre de contrôle

Lancement interactif :

```powershell
.\menu.ps1
```

Ou par double-clic :

```text
START_MENU.cmd
```

Le menu ne réimplémente pas la logique du projet. Il route les choix vers `install.ps1`, `update.ps1` ou les composants existants.

Choix principaux : installation complète, logiciels, mises à jour, sauvegarde, restauration/rollback, audit, vérification, composants spécifiques, journaux/rapports et aide.

Mode de test de routage :

```powershell
.\menu.ps1 -Choice 6 -DryRun -NoPause -NoClear
```

`-DryRun` prouve la route choisie sans exécuter la commande cible.

Guide : [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md).

---

# 2. `install.ps1` — orchestrateur principal

Syntaxe conceptuelle :

```powershell
.\install.ps1 -Mode <Audit|Apply|Verify|Rollback> [options]
```

## `-Mode Audit`

```powershell
.\install.ps1 -Mode Audit
```

**But :** observer l'état réel sans chercher à faire converger la machine.

**À utiliser :** avant toute intervention, après un changement important ou pour diagnostiquer une dérive.

**Résultat attendu :** inventaire, états des composants, journaux et faits machine.

## `-Mode Apply`

```powershell
.\install.ps1 -Mode Apply
```

**But :** vérifier les composants demandés, calculer le delta, appliquer uniquement les écarts puis re-vérifier.

Sans options supplémentaires, seuls les composants inclus dans le plan courant sont traités. La stack DevOps et OpenClaw ne sont inclus que s'ils sont demandés.

## `-Mode Verify`

```powershell
.\install.ps1 -Mode Verify
```

**But :** contrôler la conformité de la workstation sans utiliser le succès d'une ancienne installation comme preuve.

Les options `-ValidateHardware`, `-ValidateWsl`, `-ValidateDevOps` et `-ValidateOpenClawAI` étendent la qualification.

## `-Mode Rollback`

```powershell
.\install.ps1 -Mode Rollback
```

**But :** restaurer les états initiaux réellement enregistrés pour les réglages gérés et rollbackables.

Le rollback ne supprime pas automatiquement OpenClaw, Ubuntu, les données utilisateur ou les disques.

---

# 3. Prévisualiser avant modification

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

`-PlanOnly` exécute la découverte et construit le plan, puis s'arrête avant l'application.

C'est la commande recommandée pour vérifier qu'une intervention correspond bien à l'intention prévue.

---

# 4. Installation complète

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

`-FullInstall` active notamment :

- installation/validation de la stack DevOps ;
- validation WSL2 ;
- qualification matérielle ;
- intégration et validation OpenClaw prévues par le mode complet.

L'orchestrateur peut demander une action utilisateur lorsqu'une preuve ne peut pas être automatisée honnêtement.

---

# 5. Options WSL2

## `-WslProfile`

Valeurs supportées :

```text
standard
lab-heavy
nat-fallback
```

Exemple :

```powershell
.\install.ps1 -Mode Apply -WslProfile lab-heavy
```

Le profil `standard` est le profil quotidien. `lab-heavy` réserve davantage de ressources aux labs. `nat-fallback` conserve les ressources standard avec un mode réseau de repli.

## `-Distribution`

Valeur par défaut :

```text
Ubuntu
```

Le contrat runtime impose actuellement cette distribution.

## `-WslInstallLocation`

Valeur par défaut :

```text
D:\WSL\Ubuntu-DevOps
```

Une localisation incompatible avec le contrat est refusée ; le projet ne supprime pas automatiquement une distribution existante pour la déplacer.

## `-WslUser`

Permet de fournir explicitement l'utilisateur Linux lorsque sa détection n'est pas suffisante.

Ne jamais fournir de mot de passe en paramètre de commande.

---

# 6. Stack DevOps

Installer/réparer :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

Valider :

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

Valider WSL2 et DevOps ensemble :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl -ValidateDevOps
```

Les versions attendues des outils reproductibles sont définies dans `config/devops/tool-versions.env`.

---

# 7. Qualification matérielle

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

La qualification combine les faits observables par Windows et les preuves manuelles nécessaires.

Lorsque le script le demande, les preuves peuvent être enregistrées via le composant de contrôles matériels documenté dans [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

---

# 8. Profils d'optimisation Windows

Paramètre :

```text
-OptimizationProfiles
```

Valeurs supportées :

```text
standard
privacy
gaming
optional
```

Exemple :

```powershell
.\install.ps1 -Mode Apply -OptimizationProfiles standard,gaming
```

Le profil `standard` reste la base. Les profils supplémentaires sont explicites et ne doivent pas être considérés comme obligatoires pour chaque utilisateur.

Guide : [`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md).

---

# 9. Intégration OpenClaw/OpenRouter

Installer/réparer :

```powershell
.\install.ps1 -Mode Apply -InstallOpenClawAI
```

Valider :

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

Paramètres de localisation disponibles :

```text
-OpenClawRoot
-OpenClawControlPlanePath
-OpenClawRepositoryRef
```

Les valeurs par défaut placent l'intégration sous `D:\AI\OpenClaw`.

Le ref du control-plane est normalement lu depuis `config/openclaw/control-plane.json`. Une surcharge explicite doit rester une opération de qualification contrôlée.

Guide : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

# 10. Sauvegarde et reprise

`install.ps1` accepte une action de sauvegarde distincte du mode normal :

```text
-BackupAction None
-BackupAction Create
-BackupAction Verify
-BackupAction RestorePlan
```

Exemples :

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
.\install.ps1 -BackupAction RestorePlan -BackupTargetDrive E:
```

`E:` est un exemple : utiliser la lettre réelle du support de sauvegarde.

Options associées :

```text
-AllowNonUsbBackupTarget
-SkipBackupRestorePoint
```

La politique normale exige un support séparé adapté. `RestorePlan` génère un plan ; il ne transforme pas la restauration complète en action automatique.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

# 11. Options d'automatisation

## `-NonInteractive`

Indique que l'exécution ne doit pas compter sur des questions interactives ordinaires.

## `-Yes`

Confirme les changements lorsqu'une exécution non interactive doit être autorisée à poursuivre.

## `-PlanOnly`

Calcule le plan sans appliquer les changements.

Ces options ne peuvent pas inventer des preuves matérielles, secrets ou décisions humaines qui n'existent pas.

---

# 12. `update.ps1` — maintenance

Modes :

```powershell
.\update.ps1 -Mode Audit
.\update.ps1 -Mode Apply
.\update.ps1 -Mode Verify
```

Le gestionnaire couvre :

1. Windows Update ;
2. applications WinGet ;
3. runtime WSL ;
4. Ubuntu/APT ;
5. outils DevOps épinglés ;
6. extensions VS Code.

## Options sensibles

```text
-IncludeDrivers
-IncludeOptionalUpdates
-IncludeUnknownPackages
```

Elles sont opt-in. Le comportement par défaut ne sélectionne pas automatiquement toutes les catégories facultatives.

## Plan de maintenance

```powershell
.\update.ps1 -Mode Apply -PlanOnly
```

Permet de préparer le plan de maintenance avant application.

## Automatisation

```text
-NonInteractive
-Yes
-NoRestartPrompt
```

Le gestionnaire détecte si un redémarrage est requis mais ne doit pas le forcer silencieusement.

Guide : [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

# 13. Vocabulaire de sortie

| Statut | Sens opérationnel |
| --- | --- |
| `DÉJÀ OK` | aucune correction nécessaire |
| `À FAIRE` | écart détecté |
| `EN COURS` | action en cours |
| `FAIT` | modification effectuée |
| `ACTION REQUISE` | décision humaine nécessaire |
| `ATTENTE` | dépendance externe ou prochaine étape |
| `IGNORE` | hors périmètre de cette exécution |
| `AVERTISSEMENT` | situation à surveiller |
| `ERREUR` | opération non conforme |

Ce vocabulaire est volontairement orienté exploitation : il doit être possible de comprendre le statut sans lire le code source.

---

# 14. Où lire le résultat

Les sorties console sont complétées par :

```text
logs\install.log
logs\<catégorie>\<script>.log
logs\runs\<RunId>\events.ndjson
logs\runs\<RunId>\summary.json
reports\orchestration\latest-run.json
reports\orchestration\machine-state.json
reports\updates\latest-run.json
```

D'autres rapports spécialisés apparaissent lorsque les composants correspondants sont exécutés.

---

## Commandes de référence du parcours normal

```powershell
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
.\install.ps1 -Mode Apply -FullInstall
.\install.ps1 -Mode Verify -ValidateHardware -ValidateWsl -ValidateDevOps
.\update.ps1 -Mode Audit
```

Pour savoir **dans quel ordre** les utiliser, voir [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).