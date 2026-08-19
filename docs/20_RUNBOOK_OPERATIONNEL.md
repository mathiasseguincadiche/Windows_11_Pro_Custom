# Runbook opérationnel — construire, converger et qualifier la workstation

Ce runbook est la procédure officielle pour une **première convergence**, une **machine partiellement configurée** ou une **requalification globale** de `Windows_11_Pro_Custom`.

Il répond à une question opérationnelle : **que faut-il faire, dans quel ordre, comment savoir si l'étape a réussi et quand faut-il s'arrêter ?**

Il ne remplace pas :

- [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) — installation initiale de Windows ;
- [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) — reprise après incident majeur ;
- [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) — paramètres et commandes de référence.

OpenClaw/OpenRouter ne fait pas partie de ce périmètre.

## Résultat attendu

```text
Windows 11 Pro stable
+ identité physique C:/E: vérifiée
+ matériel qualifié
+ WSL2 Ubuntu 26.04 conforme
+ stack DevOps conforme
+ Windows Terminal conforme
+ PowerShell 7 - DevOps et Ubuntu - DevOps disponibles
+ preuves exploitables
+ idempotence démontrée
+ sauvegarde vérifiée
+ dérive physique expliquée ou absente
```

## Avant de commencer

### Prérequis

- Windows 11 Pro démarre normalement ;
- le dépôt est disponible localement ;
- `C:` et `E:` peuvent être identifiés ;
- aucune opération destructive concurrente n'est en cours ;
- les données importantes possèdent une sauvegarde adaptée ;
- les privilèges administrateur peuvent être obtenus lorsque l'étape le demande.

### Conditions d'arrêt immédiat

Arrêtez le parcours et diagnostiquez avant de continuer si :

- l'identité de `C:` ou `E:` est ambiguë ;
- un SSD attendu disparaît ou change de rôle sans explication ;
- une preuve matérielle obligatoire est inconnue ;
- un validateur signale une erreur que vous ne comprenez pas ;
- le plan propose une mutation inattendue ;
- un redémarrage Windows est explicitement requis.

Ne contournez pas un garde-fou pour obtenir un état vert.

---

## Étape 1 — observer l'état initial

### Objectif

Obtenir une photographie factuelle de la machine **avant toute convergence**.

### Commande

```powershell
.\install.ps1 -Mode Audit
```

### Ce que fait cette étape

Elle exécute les contrôles de découverte et produit les journaux/rapports nécessaires au diagnostic.

### Résultat attendu

Vous devez pouvoir identifier :

- ce qui est déjà conforme ;
- ce qui manque ;
- ce qui nécessite une décision humaine ;
- les éventuelles anomalies de stockage ou de matériel.

### Si l'étape échoue

Consultez [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md) et [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

---

## Étape 2 — qualifier l'identité physique du stockage

### Objectif

Prouver que `C:` et `E:` correspondent aux bons rôles physiques avant les parcours stricts.

### Première qualification uniquement

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Audit
.\scripts\bootstrap\00_storage_identity_v25.ps1 `
  -Mode Record `
  -ConfirmHealthyTopology
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Verify
```

### Contrôle humain obligatoire avant `Record`

Vérifiez que :

- `C:` est le volume Windows attendu ;
- `E:` est le second Crucial T705 NTFS destiné aux données et à WSL2 ;
- les deux rôles sont portés par deux SSD physiques distincts ;
- `E:` n'est ni un volume boot/système ni un volume caché inattendu.

### Baseline déjà existante

N'exécutez pas `Record`. Utilisez :

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Verify
```

### Condition d'arrêt

Toute divergence inexpliquée bloque la suite.

Référence : [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md).

---

## Étape 3 — calculer le plan sans modifier la machine

### Objectif

Voir exactement ce que l'orchestrateur prévoit avant d'autoriser les mutations.

### Commande

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

### Ce que signifie `FullInstall`

Le raccourci active notamment :

```text
InstallDevOps
ValidateDevOps
ValidateWsl
ValidateHardware
```

Il ne déclenche aucun projet externe.

### Interpréter le plan

| État | Signification |
| --- | --- |
| `DÉJÀ OK` | aucune modification nécessaire |
| `À FAIRE` | un écart a été détecté |
| `ACTION REQUISE` | décision ou preuve humaine nécessaire |
| `IGNORE` | élément hors du périmètre demandé |
| `ERREUR` / `KO` | conformité non démontrée |

### Condition d'arrêt

Si une action vous paraît incohérente, n'exécutez pas `Apply` tant que la source de vérité et le diagnostic ne sont pas compris.

---

## Étape 4 — faire converger la workstation

### Objectif

Appliquer uniquement les écarts validés par le plan.

### Commande

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

### Ce qui peut se produire

- une fondation déjà conforme reste inchangée ;
- un composant manquant est appliqué ;
- un redémarrage peut être demandé ;
- une preuve matérielle peut nécessiter une saisie guidée ;
- plusieurs passages peuvent être nécessaires si Windows ou WSL2 doit finaliser une étape.

### En cas de redémarrage

Redémarrez Windows lorsque le moteur le demande, puis relancez **la même intention**. L'idempotence doit empêcher la répétition inutile des étapes déjà conformes.

---

## Étape 5 — vérifier WSL2

### Contrat principal

```text
Distribution : Ubuntu
Release      : 26.04 / resolute
Emplacement  : E:\WSL\Ubuntu-DevOps
Filesystem   : ext4 dans le VHDX WSL2
Profil std.  : 20 Go RAM / 8 threads / 8 Go swap
```

### Commande

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

### Résultat attendu

La distribution, le runtime, le profil et l'emplacement sont conformes. Les projets Linux actifs vivent sous `~/projects`, `~/labs` ou `~/repositories`.

Référence : [`06_WSL2.md`](06_WSL2.md).

---

## Étape 6 — vérifier la stack DevOps

### Réparation ciblée si nécessaire

```powershell
.\install.ps1 -Mode Apply -InstallDevOps
```

### Vérification

```powershell
.\install.ps1 -Mode Verify -ValidateWsl -ValidateDevOps
```

### Résultat attendu

Les outils attendus par `config/devops/tool-versions.env` sont présents avec les versions/contrats prévus.

Référence : [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md).

---

## Étape 7 — vérifier Windows Terminal

### Objectif

Prouver que la workstation expose les deux contextes gérés :

```text
PowerShell 7 - DevOps
Ubuntu - DevOps
```

### Vérification ciblée

```powershell
.\scripts\windows\31_windows_terminal.ps1 -Mode Verify
```

Cette vérification est également intégrée au parcours général de `install.ps1 -Mode Verify`.

### Contrat utilisateur

```text
Ctrl+Shift+1 -> PowerShell 7 - DevOps
Ctrl+Shift+2 -> Ubuntu - DevOps
Ctrl+Shift+O -> PowerShell + Ubuntu en panneaux
```

Windows Terminal n'est pas propriétaire du shell Bash/Starship Linux ; cette responsabilité reste du côté WSL2.

---

## Étape 8 — qualifier le matériel

### Commande

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

### Résultat attendu

Les informations observables sont vérifiées et les contrôles impossibles à déduire honnêtement depuis Windows sont explicitement renseignés.

Si une preuve manuelle est nécessaire :

```powershell
.\scripts\windows\51_hardware_manual_checks.ps1 -Mode Record -Interactive
```

Le projet doit préférer `ACTION REQUISE` à une preuve inventée.

Référence : [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

---

## Étape 9 — vérifier la conformité globale

### Commande

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

### Résultat attendu

Aucun domaine demandé ne présente d'erreur inexpliquée. Un `Apply` terminé ne suffit pas : c'est ce `Verify` sur l'état réel qui apporte la preuve de conformité.

---

## Étape 10 — prouver l'idempotence

### Commande

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

### Résultat attendu

Les composants stabilisés tendent vers `DÉJÀ OK`.

### Condition d'arrêt

Si une même mutation revient sans raison à chaque plan, traitez-la comme une dérive ou une incohérence `Apply` ↔ `Verify`.

---

## Étape 11 — capturer la preuve physique

Après validation complète sur la workstation réelle :

```powershell
.\scripts\windows\90_workstation_fingerprint_v26.ps1 `
  -Mode Audit `
  -EvidenceLevel PHYSICAL `
  -ConfirmPhysicalEvidence
```

Selon le cycle de vie de la baseline, utilisez ensuite les modes `Verify` ou `Record` documentés dans [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md).

Une preuve `SIMULATED` ou une CI verte ne remplace pas cette étape.

---

## Étape 12 — vérifier le dispositif de sauvegarde

### Objectif

S'assurer que la workstation validée peut être récupérée.

La politique et les commandes sont documentées dans :

- [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) ;
- [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md) ;
- [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md).

Ne confondez pas « un dossier de sauvegarde existe » avec « la sauvegarde est restaurable ».

---

## Étape 13 — maintenance courante

Toujours commencer par l'audit :

```powershell
.\update.ps1 -Mode Audit
```

Prévisualisez et appliquez ensuite uniquement le périmètre voulu selon [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

Après une mise à jour structurante, rejouez la vérification globale et l'idempotence.

---

## Critères de sortie

La workstation peut être déclarée prête lorsque :

- l'état initial a été observé et compris ;
- la baseline V25 de stockage est valide ;
- le plan a été relu avant mutation ;
- Windows et le matériel sont qualifiés ;
- WSL2 respecte son contrat ;
- la stack DevOps respecte ses contrats ;
- Windows Terminal expose `PowerShell 7 - DevOps` et `Ubuntu - DevOps` ;
- les projets Linux restent sur le filesystem ext4 WSL2 ;
- OpenClaw/OpenRouter et les autres projets externes restent hors périmètre ;
- les logs et rapports expliquent les verdicts ;
- le second `PlanOnly` démontre l'idempotence ;
- la preuve `PHYSICAL` ne contient aucune dérive inexpliquée ;
- le dispositif de sauvegarde/restauration a été vérifié.

Checklist complète : [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md).

## En cas d'échec

N'essayez pas d'obtenir un état vert en supprimant un contrôle.

```text
1. identifier le domaine en erreur
2. lire le log ou le rapport
3. retrouver la source de vérité
4. comprendre l'écart
5. appliquer la correction minimale
6. rejouer le même Verify
```

Diagnostic : [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md).

Le résultat final n'est pas « le script a tourné » : c'est une **workstation DevOps/Ops reproductible, vérifiée, explicable et récupérable**.
