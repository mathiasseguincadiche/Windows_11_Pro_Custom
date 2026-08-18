# Orchestration — état réel, plan, convergence et idempotence

L'orchestration est le cœur opérationnel du projet. Elle permet de gérer une workstation réelle **sans supposer qu'elle est vide, sans réappliquer aveuglément les mêmes actions et sans utiliser un ancien fichier d'état comme vérité actuelle**.

Le point d'entrée technique principal est :

```powershell
.\install.ps1
```

Le centre de contrôle `menu.ps1` appelle cet orchestrateur ; il ne duplique pas sa logique.

Le Runbook de réalisation de bout en bout est [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).

---

## 1. Modèle mental

```text
état attendu versionné
        +
état réel de la machine
        ↓
Probe / Verify
        ↓
plan factuel
        ↓
aucun écart ? ── oui ──► DÉJÀ OK
        │
        non
        ↓
confirmation / protection
        ↓
Apply ciblé
        ↓
re-Verify
        ↓
logs + rapport + verdict
```

L'objectif n'est pas « exécuter tous les scripts ». L'objectif est **faire converger uniquement les composants qui en ont besoin**.

---

# 2. Le moteur partagé

`install.ps1` s'appuie sur :

```text
scripts/core/runtime.psm1
```

Ce module fournit notamment :

- le contexte d'exécution ;
- le `RunId` ;
- la gestion des journaux ;
- la redaction des arguments sensibles ;
- l'exécution contrôlée des sous-scripts ;
- les probes de conformité ;
- les statuts utilisateur ;
- les événements structurés ;
- la synthèse de fin d'exécution.

Le moteur permet aux composants spécialisés de conserver une expérience cohérente sans réimplémenter la logique de logs et de planification.

---

# 3. Source de vérité

Le projet distingue quatre catégories d'information :

```text
faits machine
configurations / manifests
états de rollback
logs / rapports
```

Les fichiers `state/` servent uniquement aux retours arrière qui ont besoin d'un état initial enregistré.

Ils ne sont **pas** utilisés pour dire qu'un composant est conforme aujourd'hui.

La conformité doit être recalculée depuis la machine réelle.

Guide : [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

---

# 4. Les quatre modes principaux

## Audit

```powershell
.\install.ps1 -Mode Audit
```

### But

Observer, inventorier et rendre l'état lisible.

### Comportement

L'orchestrateur exécute la découverte et plusieurs audits spécialisés sans essayer de faire converger l'ensemble.

### Quand l'utiliser

- première prise en main ;
- avant une intervention ;
- après un changement important ;
- pendant un diagnostic ;
- avant de décider si une réinstallation est vraiment nécessaire.

Audit ne signifie pas conformité.

---

## Apply

```powershell
.\install.ps1 -Mode Apply
```

### But

Faire converger les composants demandés.

### Fonctionnement

Pour chaque élément planifié :

1. exécuter le validateur ;
2. considérer la cible `DÉJÀ OK` si le validateur réussit ;
3. planifier l'Apply seulement si le validateur signale un écart ;
4. appliquer ;
5. re-vérifier.

Cette séparation est la base de l'idempotence.

---

## Verify

```powershell
.\install.ps1 -Mode Verify
```

### But

Exiger la conformité de la workstation selon les validateurs sélectionnés.

Validation étendue :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

`Verify` est le mode de décision de conformité. Il est détaillé dans [`11_VALIDATION.md`](11_VALIDATION.md).

---

## Rollback

```powershell
.\install.ps1 -Mode Rollback
```

### But

Revenir aux états initiaux que le dépôt a réellement enregistrés et sait restaurer sans ambiguïté.

Le rollback concerne surtout les réglages Windows et composants bornés.

Il ne signifie pas :

- restauration complète de disque ;
- suppression d'Ubuntu ;
- suppression automatique de projets externes ;
- retour arrière d'un changement matériel ;
- restauration magique de données utilisateur.

Le projet préfère une frontière explicite à une promesse de rollback irréaliste.

---

# 5. `FullInstall`

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

`-FullInstall` demande le parcours complet de la workstation et active :

```text
InstallDevOps
ValidateDevOps
ValidateWsl
ValidateHardware
```

Ce paramètre ne contourne pas le modèle machine-first : chaque composant doit toujours être vérifié avant d'être modifié.

La baseline d'identité physique V25 de `C:` et `E:` est un prérequis strict.
Sur une première installation, exécuter le parcours `Audit → V25 Record → V25
Verify` décrit dans [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md).

Une installation complète peut donc produire beaucoup de `DÉJÀ OK` sur une machine déjà partiellement configurée.

Elle ne clone, n'installe, ne configure et ne valide aucun projet externe.

---

# 6. `PlanOnly`

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

`PlanOnly` est le moyen le plus simple de répondre à :

> « Que ferait le projet si je lançais la convergence maintenant ? »

Le moteur réalise la phase de découverte, teste les composants, affiche le plan puis s'arrête avant les modifications.

`PlanOnly` est non mutatif, mais il utilise la préqualification physique stricte :
une baseline V25 absente ou divergente le bloque avant le calcul du plan. Ce
blocage est attendu et protège les rôles physiques de `C:` et `E:`.

À utiliser avant une intervention sensible ou pour prouver l'idempotence d'une machine déjà prête.

---

# 7. Construction du plan

Le plan repose sur une fonction logique du type :

```text
VerifyPath
   ↓
succès ?
   ├── oui -> Compliant -> DÉJÀ OK
   └── non -> NeedsChange -> À FAIRE
```

L'Apply associé n'est déclenché que pour `NeedsChange`.

Cette architecture impose une règle importante aux composants :

> **Ce que `Apply` produit doit correspondre exactement à ce que `Verify` attend.**

Si ce contrat est rompu, un composant peut boucler indéfiniment entre `À FAIRE` et `Apply`.

Le troubleshooting de cette situation est décrit dans [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md).

---

# 8. Statuts utilisateur

Le vocabulaire commun est :

```text
DÉJÀ OK
À FAIRE
EN COURS
FAIT
ACTION REQUISE
ATTENTE
IGNORE
AVERTISSEMENT
ERREUR
```

Ces statuts ont une signification opérationnelle, pas seulement esthétique.

- `DÉJÀ OK` : aucune mutation nécessaire ;
- `À FAIRE` : delta détecté ;
- `FAIT` : une action a modifié l'état ;
- `ACTION REQUISE` : l'automatisation ne peut pas inventer la décision ;
- `ERREUR` : le composant ne peut pas être déclaré conforme.

`FAIT` doit être suivi d'une re-vérification. Une modification réussie techniquement peut encore produire un état final incorrect.

---

# 9. Confirmation et protection avant changement

Lorsqu'un plan contient des modifications, l'orchestrateur peut demander une confirmation et préparer un point de restauration avant les changements Windows concernés.

Si aucune modification n'est nécessaire, le projet ne crée pas inutilement un point de restauration ni de nouvelles preuves de benchmark simplement pour « faire quelque chose ».

C'est une conséquence directe de la logique machine-first.

---

# 10. Mesures avant/après

Pour certains réglages Windows, le projet produit des mesures légères avant et après afin de comparer l'état sans lancer de benchmark agressif.

Le but est de documenter les effets d'une optimisation, pas de générer un score artificiel.

Les preuves existantes ne sont pas réécrites inutilement sur une relance totalement conforme, sauf lorsqu'une base de validation est absente.

---

# 11. Actions humaines

Certaines informations restent nécessairement humaines :

- contrôles BIOS/UEFI ;
- ReBAR / Above 4G ;
- stabilité mémoire ;
- emplacement physique des SSD ;
- choix de restauration ;
- saisie de secrets ;
- création/confirmation de certains éléments utilisateur ;
- redémarrages demandés par le système.

Le moteur doit les rendre visibles comme `ACTION REQUISE` plutôt que simuler un succès.

---

# 12. WSL2 dans l'orchestration

Le composant WSL vérifie notamment :

- disponibilité de WSL ;
- nom de distribution ;
- mode WSL2 ;
- profil `.wslconfig` ;
- emplacement sur `E:` ;
- release Ubuntu attendue ;
- préconditions de stockage.

Une distribution existante mais incompatible n'est pas supprimée automatiquement. L'orchestrateur s'arrête avec un état explicite afin que l'utilisateur décide de la migration appropriée.

Guide : [`06_WSL2.md`](06_WSL2.md).

---

# 13. DevOps dans l'orchestration

La stack DevOps est volontairement opt-in dans un `Apply` standard :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

`-FullInstall` l'inclut.

Cette séparation permet d'auditer ou de corriger Windows sans réinstaller la couche Linux DevOps lorsqu'elle n'est pas demandée.

La validation DevOps reste disponible séparément.

---

# 14. Projets externes dans l'orchestration

L'orchestrateur ne possède pas les projets externes installés éventuellement sur la même machine.

En particulier, OpenClaw/OpenRouter n'est pas un composant de `install.ps1` : il n'existe plus de paramètre `InstallOpenClawAI`, `ValidateOpenClawAI`, `OpenClawRoot`, `OpenClawControlPlanePath` ou `OpenClawRepositoryRef`, ni de pin `config/openclaw/control-plane.json`.

L'installation, la configuration, la maintenance et la validation de cette plateforme appartiennent au dépôt `mathiasseguincadiche/openclaw_openrouter`.

Guide de frontière : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

# 15. Journaux et événements

Chaque run possède un identifiant unique et peut produire :

```text
logs\install.log
logs\<catégorie>\<script>.log
logs\runs\<RunId>\events.ndjson
logs\runs\<RunId>\summary.json
reports\orchestration\latest-run.json
```

Les événements structurés enregistrent notamment le script, la phase, le résultat, la durée et le chemin du log.

Les arguments dont le nom indique une donnée sensible sont masqués dans la représentation journalisée.

---

# 16. Non-interactif

Les options d'automatisation comprennent notamment :

```text
-NonInteractive
-Yes
-PlanOnly
```

Elles sont utiles en automatisation ou en CI, mais elles ne doivent pas contourner une frontière qui nécessite réellement une action humaine.

Par exemple, une preuve matérielle impossible à observer ne devient pas vraie parce qu'une exécution est non interactive.

---

# 17. Relation avec `update.ps1`

`install.ps1` gère la conformité de la workstation.

`update.ps1` gère la maintenance de plusieurs couches : Windows Update, WinGet, runtime WSL, Ubuntu, outils DevOps épinglés et extensions VS Code.

Les deux moteurs partagent la philosophie :

```text
observer
→ planifier
→ appliquer uniquement ce qui est nécessaire
→ re-vérifier
```

Guide : [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

# 18. Critère de réussite de l'orchestration

Une exécution est satisfaisante lorsque :

```text
état réel lu
+
plan cohérent
+
actions nécessaires uniquement
+
re-vérification réussie
+
actions humaines visibles
+
preuves disponibles
```

Mais le **projet complet** demande encore la qualification et les critères d'acceptation décrits dans :

- [`11_VALIDATION.md`](11_VALIDATION.md) ;
- [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md) ;
- [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md).

C'est cette distinction entre **orchestrer** et **valider le projet** qui empêche de confondre « le script a tourné » avec « la workstation est prête ».
