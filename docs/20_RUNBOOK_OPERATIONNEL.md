# Runbook opérationnel — réaliser et valider le projet

Ce document est le **parcours officiel de mise en œuvre** de `Windows_11_Pro_Custom`.

Il décrit l'ordre des opérations, la différence entre observation, convergence et validation, et les critères permettant de déclarer la workstation prête.

Il ne remplace pas :

- [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) — installation de Windows depuis zéro ;
- [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) — reprise après incident ;
- [`11_VALIDATION.md`](11_VALIDATION.md) — mécanismes de preuve et de validation.

## Résultat attendu

```text
Windows 11 Pro stable et qualifié
+ applications et réglages attendus
+ WSL2 Ubuntu 26.04 sous D:\WSL\Ubuntu-DevOps
+ projets Linux sur ext4
+ stack DevOps qualifiée
+ terminal / VS Code cohérents
+ OpenClaw CLI via WezTerm si l'intégration est utilisée
+ logs et rapports exploitables
+ idempotence démontrée
+ sauvegarde de référence vérifiée
```

OpenClaw/OpenRouter est une intégration distincte dans l'architecture. Le raccourci `-FullInstall` **OpenClaw inclus dans l'orchestration**, mais uniquement par délégation au control-plane `openclaw_openrouter` : l'installation du runtime IA, OpenRouter, `clawops`, Gateway, modèles et agents reste possédée par ce dépôt spécialisé.

---

## Deux parcours d'installation

### Workstation core, sans OpenClaw

C'est le parcours recommandé lorsque l'intégration IA n'est pas souhaitée ou lorsque l'on veut maintenir strictement le périmètre workstation :

```powershell
.\install.ps1 `
  -Mode Apply `
  -InstallDevOps `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateHardware
```

### Agrégation complète, OpenClaw inclus par délégation

Le code actuel de `install.ps1` définit `-FullInstall` comme un raccourci qui active :

```text
InstallDevOps
ValidateDevOps
ValidateWsl
ValidateHardware
InstallOpenClawAI
ValidateOpenClawAI
```

Utiliser :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

lorsque l'on veut enchaîner la convergence de la workstation et l'intégration IA en une seule intention.

Ce raccourci ne fusionne pas les dépôts : `InstallOpenClawAI` appelle le pont d'intégration Windows, qui synchronise le control-plane approuvé puis délègue l'installation au code de `openclaw_openrouter`.

---

# Étape 1 — comprendre le périmètre

Lire au minimum :

1. [`../README.md`](../README.md) ;
2. [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) ;
3. ce Runbook ;
4. [`11_VALIDATION.md`](11_VALIDATION.md).

La base Windows doit être exploitable avec les volumes `C:` et `D:` correctement identifiés, les pilotes essentiels présents et les prérequis firmware nécessaires à Windows 11 / WSL2 disponibles.

Les éléments qui nécessitent une preuve matérielle ou firmware sont traités dans [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

---

# Étape 2 — établir l'état réel

Depuis la racine du dépôt :

```powershell
.\install.ps1 -Mode Audit
```

L'audit observe la machine avant toute convergence. Il produit les faits nécessaires au diagnostic et alimente `logs\` / `reports\`.

Ne corrige pas plusieurs composants à l'aveugle lorsqu'un audit signale un écart : identifie d'abord le contrat concerné et le journal associé.

---

# Étape 3 — calculer le plan sans modifier

## Core sans OpenClaw

```powershell
.\install.ps1 `
  -Mode Apply `
  -InstallDevOps `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateHardware `
  -PlanOnly
```

## Agrégation complète avec OpenClaw délégué

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

`-PlanOnly` calcule le plan depuis l'état réel puis s'arrête avant l'application.

Les statuts essentiels sont :

| État | Signification |
| --- | --- |
| `DÉJÀ OK` | composant conforme |
| `À FAIRE` | écart détecté |
| `ACTION REQUISE` | décision ou preuve humaine nécessaire |
| `IGNORE` | composant hors du périmètre demandé |
| `ERREUR` | conformité non démontrée |

Une machine déjà partiellement conforme doit produire un plan partiel, pas une réinstallation générale.

---

# Étape 4 — faire converger la workstation

Pour le périmètre core :

```powershell
.\install.ps1 `
  -Mode Apply `
  -InstallDevOps `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateHardware
```

Pour l'agrégation complète avec extension IA déléguée :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

Le moteur vérifie chaque composant, applique uniquement le delta puis re-vérifie les éléments demandés. Pour OpenClaw/OpenRouter, l'application réelle reste exécutée par le control-plane spécialisé.

Lorsqu'une action humaine est demandée, la traiter puis relancer la même intention : les composants déjà conformes doivent rester idempotents.

Voir [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md).

---

# Étape 5 — vérifier WSL2

Contrat courant :

```text
Distribution : Ubuntu
Release      : 26.04 / resolute
Emplacement  : D:\WSL\Ubuntu-DevOps
Filesystem   : ext4 dans le VHDX WSL2
Profil       : standard = 20 Go RAM / 8 threads / 8 Go swap
```

Les projets DevOps Linux doivent vivre sous `~/projects`, `~/labs` ou `~/repositories`.

Validation ciblée :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

Voir [`06_WSL2.md`](06_WSL2.md).

---

# Étape 6 — vérifier la stack DevOps et le terminal

Installation/réparation DevOps ciblée :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

Validation DevOps :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl -ValidateDevOps
```

La configuration WezTerm appartient à la workstation elle-même et est vérifiée par :

```powershell
.\install.ps1 -Mode Verify
```

Le résultat attendu conserve les trois contextes : Ubuntu DevOps par défaut, PowerShell 7 Windows et OpenClaw/clawops Windows lorsque l'intégration IA est utilisée.

Les versions reproductibles DevOps sont définies dans `config/devops/tool-versions.env`.

Voir [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md).

---

# Étape 7 — qualifier le matériel

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

Certaines preuves restent manuelles lorsque Windows ne peut pas les déterminer honnêtement. Le projet doit alors produire `ACTION_REQUISE` plutôt qu'un verdict positif inventé.

Voir [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

---

# Étape 8 — OpenClaw/OpenRouter et accès CLI

Si l'intégration n'a pas été demandée dans le parcours core, elle peut être ajoutée explicitement :

```powershell
.\install.ps1 -Mode Apply -InstallOpenClawAI
```

Cette commande est un **point de délégation** : `Windows_11_Pro_Custom` sélectionne le control-plane approuvé et lui transmet l'installation. Les procédures runtime et OpenRouter ne sont pas réimplémentées ici.

Puis l'intégration locale peut être validée :

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

Si `-FullInstall` a été utilisé, ces deux intentions ont déjà été activées par le raccourci, toujours par délégation au dépôt `openclaw_openrouter`.

Une fois l'intégration validée :

1. ouvrir WezTerm ;
2. choisir `OpenClaw / clawops (Windows)` ;
3. confirmer que le profil indique les deux CLI disponibles ;
4. effectuer le smoke test CLI.

```powershell
openclaw --version
clawops version
clawops platform check
```

Le profil recharge lui-même dans sa session les variables et chemins gérés nécessaires ; une relance préalable de WezTerm n'est pas requise uniquement pour rafraîchir cet environnement.

Ce smoke test prouve l'accès utilisateur aux CLI depuis le terminal prévu. Il ne remplace pas `-ValidateOpenClawAI`.

Les secrets restent hors de Git.

Voir [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

# Étape 9 — validation finale

Core :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

Avec OpenClaw :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateOpenClawAI
```

Un `Apply` terminé n'est pas une preuve suffisante. La validation repose sur l'état réellement observé.

Voir [`11_VALIDATION.md`](11_VALIDATION.md).

---

# Étape 10 — prouver l'idempotence

Rejouer le même périmètre en `PlanOnly`.

Core :

```powershell
.\install.ps1 `
  -Mode Apply `
  -InstallDevOps `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateHardware `
  -PlanOnly
```

Agrégation complète avec OpenClaw délégué :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Une workstation conforme doit tendre vers `DÉJÀ OK`. Un composant qui revient systématiquement en `À FAIRE` indique une dérive ou une vérification non stabilisée.

---

# Étape 11 — maintenance

Toujours commencer par :

```powershell
.\update.ps1 -Mode Audit
```

Puis utiliser `PlanOnly`, `Apply` et `Verify` selon le besoin. Les catégories facultatives de mise à jour restent opt-in.

Voir [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

# Étape 12 — sauvegarde de référence

Une workstation validée doit être récupérable.

Créer puis vérifier la sauvegarde sur le support prévu par la politique du dépôt. La génération d'un plan de reprise complète la validation du dispositif de recovery.

Voir [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) et [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md).

---

## Critères de sortie

Le projet peut être déclaré prêt lorsque :

- l'audit initial est compris ;
- le périmètre choisi, core ou agrégé, est explicite ;
- le plan est cohérent ;
- les écarts ont convergé ;
- Windows et le matériel sont qualifiés ;
- WSL2 respecte son contrat ;
- la stack DevOps est qualifiée ;
- WezTerm respecte le contrat des trois contextes ;
- OpenClaw est qualifié si le périmètre l'inclut ;
- le profil WezTerm OpenClaw est exploitable si OpenClaw est utilisé ;
- les frontières Windows/Linux sont respectées ;
- les responsabilités de `Windows_11_Pro_Custom` et `openclaw_openrouter` restent distinctes ;
- les logs et rapports expliquent le verdict ;
- le second plan démontre l'idempotence ;
- la sauvegarde de référence est vérifiée.

Checklist complète : [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md).

## En cas d'échec

Ne contourne pas un validateur. Lis le log, identifie la source de vérité, corrige la cause puis relance le même `Verify` ou l'`Apply` ciblé.

Voir [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) et [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

Le résultat final n'est pas « le script a tourné » : c'est une **workstation DevOps/Ops reproductible, vérifiée, explicable et récupérable**.