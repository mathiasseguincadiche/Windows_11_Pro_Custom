# Orchestration — état réel, convergence et idempotence

L'orchestration est le mécanisme qui permet au dépôt de gérer une workstation réelle **sans réinstaller ou modifier aveuglément ce qui est déjà correct**.

Le point d'entrée technique principal est :

```powershell
.\install.ps1
```

Le menu interactif appelle cet orchestrateur ; il ne duplique pas sa logique.

## Modèle de fonctionnement

```text
Découvrir l'état réel
        ↓
Vérifier chaque composant
        ↓
Construire un plan complet
        ↓
Aucun écart ? ── oui ──► ne rien modifier
        │
        non
        ↓
Confirmer les actions utiles
        ↓
Appliquer uniquement le delta
        ↓
Re-vérifier
        ↓
Journaliser + produire un verdict
```

L'objectif n'est pas « exécuter tous les scripts ». L'objectif est **faire converger la machine vers l'état attendu**.

## Les quatre modes principaux

### Audit

Observe et collecte les faits sans chercher à modifier la machine.

```powershell
.\install.ps1 -Mode Audit
```

À utiliser pour comprendre la situation avant une installation, après une mise à jour importante ou pendant un diagnostic.

### Apply

Calcule le plan puis applique les changements nécessaires.

```powershell
.\install.ps1 -Mode Apply
```

Installation complète :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

### Verify

Contrôle que la machine correspond à l'état attendu.

```powershell
.\install.ps1 -Mode Verify
```

Validation étendue :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

### Rollback

Restaure les éléments pour lesquels le dépôt possède un état initial fiable et une procédure de retour sûre.

```powershell
.\install.ps1 -Mode Rollback
```

Un rollback applicatif n'est pas une restauration bare-metal. Les opérations destructives restent séparées de l'orchestration normale.

## Prévisualiser sans mutation

Pour calculer le plan complet sans appliquer les changements :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Ce mode est utile pour :

- comprendre ce qui serait modifié ;
- vérifier qu'une machine presque conforme ne déclenche pas une réinstallation inutile ;
- préparer une intervention ;
- diagnostiquer un écart avant de l'accepter.

## État machine et sources de vérité

Le moteur distingue :

1. **faits machine** — état réellement observé ;
2. **configuration versionnée** — état attendu ;
3. **état de rollback** — information conservée uniquement pour revenir en arrière ;
4. **logs et rapports** — preuve d'une exécution.

Les fichiers de rollback ne doivent jamais être utilisés comme preuve que la machine est actuellement conforme.

## Idempotence

Une deuxième exécution sur une machine déjà conforme doit tendre vers :

```text
DÉJÀ OK
```

plutôt que vers une nouvelle mutation.

Exemples de composants vérifiés avant action :

- applications WinGet ;
- PowerShell / OpenSSH ;
- VS Code / WezTerm ;
- WSL2 ;
- utilisateur Ubuntu ;
- outils DevOps ;
- réglages Windows ;
- Defender ;
- OpenClaw lorsque cette intégration est activée.

## Réversibilité

Le dépôt privilégie le triptyque :

```text
mesurer l'état initial
        ↓
appliquer un changement borné
        ↓
pouvoir revenir à l'état initial
```

Cela concerne surtout les réglages Windows et les composants dont l'état précédent peut être enregistré sans ambiguïté.

À l'inverse, le dépôt **ne prétend pas rollbacker automatiquement** :

- un flash BIOS ;
- un changement physique de SSD ;
- une fréquence mémoire ;
- une restauration bare-metal ;
- des données utilisateur supprimées.

## Actions nécessitant l'utilisateur

Certaines validations sont explicitement marquées comme action humaine :

- contrôles BIOS/UEFI ;
- validation ReBAR / Above 4G ;
- stabilité mémoire ;
- présence physique des SSD aux bons emplacements ;
- choix de restauration destructive ;
- redémarrage lorsqu'il est nécessaire ;
- saisie de secrets ou mots de passe.

Le projet préfère une **ACTION_REQUISE honnête** à un faux succès.

## Journaux

Chaque exécution importante conserve des informations persistantes :

```text
logs/<catégorie>/<script>.log
logs/runs/<RunId>/events.ndjson
logs/runs/<RunId>/summary.json
reports/
```

Les événements détaillent ce qui a été observé, planifié, appliqué et vérifié.

Les arguments sensibles sont masqués autant que possible ; un secret ne doit jamais être ajouté volontairement dans Git ou dans une ligne de commande journalisée.

## Exécution non interactive

Certaines opérations supportent des options destinées à l'automatisation ou aux tests :

```text
-NonInteractive
-Yes
-PlanOnly
```

Ces options ne doivent pas contourner les frontières de sécurité : une restauration destructrice ou une preuve matérielle impossible à automatiser reste une décision humaine.

## Relation avec le Control Center

```text
utilisateur
   ↓
menu.ps1
   ↓
install.ps1 / update.ps1
   ↓
composants spécialisés
```

Le menu sert à choisir une intention ; l'orchestrateur reste la source de vérité de l'installation et de la convergence.

Guide du menu : [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md).

## Relation avec les mises à jour

Les mises à jour possèdent leur propre orchestrateur :

```powershell
.\update.ps1
```

Il applique les mêmes principes : audit, action ciblée et vérification finale. Voir [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

## Critère de réussite

Une opération n'est considérée réussie que si :

```text
le plan était cohérent
+
les changements nécessaires ont été appliqués
+
le nouvel état a été re-vérifié
+
aucun blocage important n'est masqué
```

Ce comportement est la base qui permet au dépôt de fonctionner comme une **workstation-as-code** plutôt que comme un simple dossier de scripts PowerShell.
