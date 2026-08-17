# Gestion des mises à jour

La workstation regroupe plusieurs couches qui ne se mettent pas à jour de la même manière : Windows, applications WinGet, WSL, Ubuntu, outils DevOps épinglés et extensions VS Code.

Le dépôt centralise leur maintenance derrière :

```powershell
.\update.ps1
```

L'objectif n'est pas de « tout mettre à la dernière version » mais de **mettre à jour sans perdre la reproductibilité ni casser la plateforme**.

## Modèle

```text
état actuel
   ↓
audit des mises à jour
   ↓
politique du dépôt
   ↓
changements autorisés
   ↓
application
   ↓
revalidation
```

## Modes

Audit :

```powershell
.\update.ps1 -Mode Audit
```

Application :

```powershell
.\update.ps1 -Mode Apply
```

Vérification :

```powershell
.\update.ps1 -Mode Verify
```

## Windows Update

Le gestionnaire peut traiter les mises à jour Windows tout en conservant des limites claires :

- pas de redémarrage forcé ;
- drivers facultatifs exclus par défaut ;
- mises à jour facultatives exclues par défaut ;
- le besoin de redémarrage reste visible ;
- le BIOS et les firmwares ne sont pas flashés automatiquement.

Les pilotes critiques restent une décision contrôlée à partir des sources AMD, Intel, MSI ou Microsoft appropriées.

## Applications WinGet

Les applications gérées par le dépôt peuvent être mises à jour via WinGet.

La politique respecte :

- les packages réellement présents ;
- les exclusions ou pins du dépôt ;
- les applications volontairement manuelles lorsqu'aucun identifiant fiable n'est retenu.

Le catalogue courant est documenté dans [`08_APPLICATIONS.md`](08_APPLICATIONS.md).

## WSL

Le runtime WSL est géré séparément de la distribution Linux.

Le dépôt peut vérifier et mettre à jour WSL sans confondre :

```text
WSL runtime Windows
≠
Ubuntu / APT
```

Après un changement important de WSL, la plateforme doit être revalidée avec :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

## Ubuntu / APT

La distribution Ubuntu suit une maintenance prudente :

- `apt update` ;
- mise à jour des paquets dans le cadre prévu ;
- pas de `dist-upgrade` automatique vers une nouvelle distribution ;
- pas d'`autoremove` agressif ;
- validation du runtime après changement.

Le changement de version Ubuntu est un **projet de migration**, pas une simple mise à jour de routine.

## Outils DevOps épinglés

Terraform, certains outils qualité et d'autres composants sensibles sont versionnés par le dépôt.

Ils ne doivent pas être remplacés aveuglément par `latest`.

La réconciliation AWS CLI conserve le même niveau de confiance que
l'installation initiale : archive et signature officielles sont téléchargées,
l'empreinte complète de la clé AWS est contrôlée, puis la signature PGP est
validée avant toute installation.

La logique est :

```text
version souhaitée dans le dépôt
        ↓
version réellement installée
        ↓
aucun delta ? ne rien faire
        ↓
delta ? installer la version validée
        ↓
re-vérifier
```

Cela protège les labs et projets contre les changements de comportement inattendus d'une nouvelle version majeure.

## Extensions VS Code

Les extensions Windows et WSL sont gérées séparément lorsque nécessaire.

Une extension peut être mise à jour, mais le dépôt garde la distinction entre :

- UI VS Code Windows ;
- extensions exécutées côté WSL ;
- configuration versionnée ;
- secrets locaux non commités.

## Ce que le gestionnaire refuse

La maintenance normale ne doit jamais :

- flasher automatiquement le BIOS ;
- installer arbitrairement tous les drivers facultatifs ;
- forcer un reboot ;
- lancer un changement majeur d'Ubuntu ;
- remplacer les outils DevOps épinglés par des versions non qualifiées ;
- supprimer agressivement des paquets ou données ;
- désactiver Defender ou le firewall pour « faire passer » une mise à jour.

## Après une grosse mise à jour

Après une mise à jour structurante :

```powershell
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Verify -ValidateHardware -ValidateWsl -ValidateDevOps
```

Si OpenClaw fait partie de la workstation :

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

Puis, lorsque la machine est stabilisée, envisager une nouvelle sauvegarde de référence.

## Rapport et diagnostic

Les opérations de mise à jour alimentent les journaux et rapports du dépôt afin de pouvoir répondre à trois questions :

1. qu'est-ce qui était installé avant ?
2. qu'est-ce qui a réellement changé ?
3. la machine est-elle encore conforme après le changement ?

Le Control Center expose ces opérations sans cacher leur nature. Voir [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md).
