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
+ logs et rapports exploitables
+ idempotence démontrée
+ sauvegarde de référence vérifiée
```

OpenClaw/OpenRouter ne fait pas partie de ce périmètre. Son installation et sa configuration appartiennent au dépôt `mathiasseguincadiche/openclaw_openrouter`.

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

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Le raccourci `-FullInstall` active uniquement :

```text
InstallDevOps
ValidateDevOps
ValidateWsl
ValidateHardware
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

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

Le moteur vérifie chaque composant, applique uniquement le delta puis re-vérifie les éléments demandés.

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

Le résultat attendu conserve deux contextes :

```text
Ubuntu DevOps (WSL2) -> profil par défaut
PowerShell 7         -> administration Windows
```

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

# Étape 8 — vérifier la frontière avec les projets externes

`Windows_11_Pro_Custom` ne doit pas installer ou configurer OpenClaw/OpenRouter.

Vérifier notamment que :

- `install.ps1` n'expose pas de paramètre OpenClaw ;
- le menu ne propose pas d'installation OpenClaw/OpenRouter ;
- aucun bootstrap ne clone ou n'exécute `openclaw_openrouter` ;
- WezTerm ne contient pas de profil OpenClaw spécifique ;
- la conformité de la workstation ne dépend pas de `D:\AI\OpenClaw`.

Voir [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

# Étape 9 — validation finale

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

Un `Apply` terminé n'est pas une preuve suffisante. La validation repose sur l'état réellement observé.

Voir [`11_VALIDATION.md`](11_VALIDATION.md).

---

# Étape 10 — prouver l'idempotence

Rejouer le même périmètre en `PlanOnly` :

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
- le plan est cohérent ;
- les écarts ont convergé ;
- Windows et le matériel sont qualifiés ;
- WSL2 respecte son contrat ;
- la stack DevOps est qualifiée ;
- WezTerm respecte le contrat Ubuntu DevOps + PowerShell 7 ;
- les frontières Windows/Linux sont respectées ;
- les projets externes restent hors du périmètre de l'orchestrateur ;
- les logs et rapports expliquent le verdict ;
- le second plan démontre l'idempotence ;
- la sauvegarde de référence est vérifiée.

Checklist complète : [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md).

## En cas d'échec

Ne contourne pas un validateur. Lis le log, identifie la source de vérité, corrige la cause puis relance le même `Verify` ou l'`Apply` ciblé.

Voir [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) et [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

Le résultat final n'est pas « le script a tourné » : c'est une **workstation DevOps/Ops reproductible, vérifiée, explicable et récupérable**.
