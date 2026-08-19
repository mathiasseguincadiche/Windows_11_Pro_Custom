# Gestion des mises à jour

La workstation contient plusieurs couches qui n'ont ni le même cycle de vie ni le même niveau de risque : Windows, applications WinGet, runtime WSL, Ubuntu, outils DevOps épinglés et extensions VS Code.

Le point d'entrée de maintenance est :

```powershell
.\update.ps1
```

L'objectif n'est pas de « tout mettre à la dernière version », mais de **mettre à jour sans perdre la reproductibilité ni casser les contrats de la workstation**.

## Principe

```text
état actuel
   ↓
Audit
   ↓
politique du dépôt
   ↓
changements autorisés
   ↓
Apply
   ↓
Verify
   ↓
revalidation globale si nécessaire
```

## Modes

Audit :

```powershell
.\update.ps1 -Mode Audit
```

Prévisualisation avant mutation :

```powershell
.\update.ps1 -Mode Apply -PlanOnly
```

Application :

```powershell
.\update.ps1 -Mode Apply
```

Vérification :

```powershell
.\update.ps1 -Mode Verify
```

Les options exactes et catégories facultatives sont référencées dans [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md).

## Windows Update

La maintenance Windows conserve des limites claires :

- pas de redémarrage forcé par défaut ;
- drivers facultatifs exclus sauf demande explicite ;
- mises à jour facultatives exclues sauf demande explicite ;
- besoin de redémarrage visible ;
- aucun flash BIOS/firmware automatique.

Les pilotes critiques restent une décision contrôlée à partir des sources appropriées AMD, Intel, MSI ou Microsoft.

## Applications WinGet

Le dépôt ne traite que les applications déclarées par son catalogue.

La politique respecte :

- les packages réellement présents ;
- les identifiants WinGet versionnés ;
- les applications `autoInstall=false` ;
- les exclusions et décisions manuelles du dépôt.

Catalogue : [`08_APPLICATIONS.md`](08_APPLICATIONS.md).

## Runtime WSL et Ubuntu

Ces deux couches sont distinctes :

```text
runtime WSL Windows
≠
distribution Ubuntu / APT
```

Après une modification importante du runtime WSL :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

La maintenance Ubuntu reste prudente :

- mise à jour des index APT ;
- mise à jour des paquets dans le cadre prévu ;
- pas de changement automatique vers une nouvelle release Ubuntu ;
- pas d'`autoremove` agressif ;
- revalidation du runtime après changement.

Un changement de release Ubuntu est un projet de migration, pas une maintenance courante.

## Outils DevOps épinglés

Les versions sensibles sont pilotées par les contrats du dépôt, notamment `config/devops/tool-versions.env`.

```text
version attendue
   ↓
version installée
   ↓
identique ? ne rien faire
   ↓
différente ? appliquer la version qualifiée
   ↓
re-vérifier
```

Une version plus récente sur Internet n'est pas automatiquement la nouvelle cible.

La réconciliation AWS CLI conserve les contrôles de confiance prévus par le projet : source officielle, empreinte de clé et validation de signature.

## VS Code

Les composants Windows et WSL peuvent avoir des responsabilités différentes. La maintenance doit conserver la distinction entre :

- interface VS Code Windows ;
- extensions exécutées côté WSL ;
- configuration versionnée ;
- secrets locaux non commités.

## Ce que la maintenance refuse

Une maintenance normale ne doit jamais :

- flasher automatiquement le BIOS ;
- installer arbitrairement tous les drivers facultatifs ;
- forcer un reboot non demandé ;
- lancer une migration majeure Ubuntu ;
- remplacer les versions DevOps épinglées par un `latest` non qualifié ;
- supprimer agressivement des paquets ou des données ;
- désactiver Defender ou le firewall pour « faire passer » une mise à jour ;
- lancer la maintenance d'un projet externe.

## Après une mise à jour structurante

Revenez à la réalité observée :

```powershell
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Verify -ValidateHardware -ValidateWsl -ValidateDevOps
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Le dernier `PlanOnly` permet de vérifier que la maintenance n'a pas créé une dérive permanente.

OpenClaw/OpenRouter est hors périmètre : sa maintenance et ses validations appartiennent au dépôt `mathiasseguincadiche/openclaw_openrouter`.

Lorsque la workstation est de nouveau stable et qualifiée, évaluez la création d'une nouvelle sauvegarde de référence selon [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

## Rapport et diagnostic

Une opération de maintenance doit permettre de répondre à trois questions :

1. qu'est-ce qui était installé avant ?
2. qu'est-ce qui a réellement changé ?
3. la workstation respecte-t-elle encore ses contrats ?

Le centre de contrôle expose ces opérations sans masquer leur nature. Voir [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md).
