# Glossaire — Windows 11 Pro Custom

Ce glossaire définit les termes utilisés dans la documentation. Il ne remplace pas les contrats techniques : lorsqu'une valeur exacte est nécessaire, utilisez le document spécialisé ou la source de vérité indiquée dans [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

## A

### `ACTION REQUISE`

État indiquant qu'une décision, une preuve ou une intervention humaine est nécessaire avant de pouvoir conclure à la conformité.

Le projet préfère cet état à un résultat positif inventé lorsque l'information n'est pas observable automatiquement.

### `Apply`

Mode qui applique les changements nécessaires pour faire converger l'état réel vers le contrat attendu.

Un `Apply` réussi ne suffit pas à prouver la conformité : il doit être suivi d'un `Verify`.

### `Audit`

Mode d'observation. Il collecte l'état réel sans exiger que tout soit déjà conforme.

Un audit peut donc réussir tout en signalant des écarts.

## B

### Baseline

État de référence explicitement approuvé et enregistré. Les observations futures peuvent être comparées à cette référence afin de détecter une dérive.

Une baseline ne doit pas être remplacée uniquement pour supprimer une alerte.

## C

### Contrat

Description versionnée d'un état attendu : configuration WSL, versions DevOps, profils Windows Terminal, catalogue WinGet, matériel cible, etc.

### Convergence

Processus qui transforme uniquement les écarts nécessaires pour rapprocher l'état réel du contrat attendu.

## D

### `DÉJÀ OK`

État indiquant que le composant contrôlé est déjà conforme et qu'aucune mutation n'est nécessaire.

### Drift / dérive

Différence entre un état de référence approuvé et l'état observé ultérieurement.

Une dérive peut être légitime, accidentelle ou problématique ; elle doit être comprise avant de modifier la baseline.

## E

### ext4

Filesystem Linux utilisé à l'intérieur du VHDX de la distribution WSL2.

Dans ce projet, les workspaces Linux actifs vivent sur ext4 sous `/home/...`, pas sur une partition ext4 physique séparée.

## F

### `FullInstall`

Option de `install.ps1` qui demande le parcours global de convergence/validation de la workstation. Elle active notamment les intentions DevOps, WSL et matériel prévues par l'orchestrateur.

Elle ne déclenche aucun projet externe.

## G

### Golden Backup

Sauvegarde de référence produite après qualification de la workstation et destinée à la reprise.

Son existence seule n'est pas suffisante : sa structure et sa restaurabilité doivent être vérifiées.

## I

### Idempotence

Propriété d'une opération qui peut être relancée sans réappliquer inutilement ce qui est déjà conforme.

Dans ce projet, un second `PlanOnly` après convergence doit tendre vers `DÉJÀ OK`.

## P

### `PHYSICAL`

Niveau de preuve produit sur la workstation réelle avec les confirmations physiques nécessaires.

Une CI ou une simulation ne peut pas être présentée comme une preuve `PHYSICAL`.

### `PlanOnly`

Option qui calcule le plan de changements sans exécuter les mutations prévues.

Elle permet de relire et comprendre ce qui serait modifié avant `Apply`.

### Preflight

Contrôles exécutés avant la convergence afin de vérifier que les fondations et conditions bloquantes sont suffisamment saines pour continuer.

## R

### `Rollback`

Retour contrôlé vers un état initial réellement enregistré pour certains réglages gérés par le dépôt.

Il ne s'agit pas d'une restauration complète de Windows ni d'un remplacement d'une sauvegarde bare-metal.

### Runbook

Procédure opérationnelle destinée à être exécutée dans un ordre précis.

Un runbook doit indiquer l'objectif, les prérequis, la commande, le résultat attendu, les preuves et les conditions d'arrêt.

### RunId

Identifiant d'une exécution utilisé pour relier des événements, logs et rapports produits pendant un même parcours.

## S

### Source de vérité

Élément qui possède la valeur de référence lorsqu'il existe plusieurs représentations possibles : configuration, manifeste, script, état observé ou documentation.

Voir [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

### `SIMULATED`

Niveau de preuve obtenu dans un environnement simulé ou sans prétendre représenter la réalité physique complète de la workstation.

### `STATIC`

Niveau de preuve portant sur la cohérence statique du dépôt : code, fichiers, contrats, lint, structure ou relations vérifiables sans workstation physique.

## V

### VHDX

Fichier de disque virtuel utilisé par WSL2 pour stocker le filesystem Linux d'une distribution.

Dans ce projet, le VHDX d'Ubuntu est géré sous `E:\WSL\Ubuntu-DevOps`.

### `Verify`

Mode qui exige que l'état observé respecte les contrats du périmètre demandé.

Contrairement à `Audit`, `Verify` peut échouer parce qu'un écart réel existe.

## W

### Windows Terminal

Terminal Windows utilisé comme point d'entrée vers les deux contextes gérés :

```text
PowerShell 7 - DevOps
Ubuntu - DevOps
```

Il ne remplace pas le shell Bash d'Ubuntu.

### Workstation-as-code

Approche consistant à traiter la configuration du poste de travail comme un système versionné, observable, convergent et vérifiable.

Le principe est :

```text
observer → comparer → planifier → appliquer → vérifier → prouver
```

### WSL2

Windows Subsystem for Linux 2. Il fournit une VM Linux légère intégrée à Windows.

Dans ce projet, WSL2 héberge Ubuntu 26.04 et la stack DevOps Linux.

## Repères rapides

| Je rencontre ce terme | Document principal |
| --- | --- |
| identité stockage / identité stockage | [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md) |
| STATIC / SIMULATED / PHYSICAL | [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md) |
| WSL2 / VHDX / ext4 | [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md) |
| Audit / Apply / Verify | [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md) |
| sauvegarde / restauration | [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) |
| commandes exactes | [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) |
