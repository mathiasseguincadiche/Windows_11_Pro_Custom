# Runbook opérationnel — réaliser et valider le projet

Ce document est le **parcours officiel de mise en œuvre** de `Windows_11_Pro_Custom`.

Il explique dans quel ordre réaliser le projet sur la machine cible, comment distinguer observation, planification, convergence et validation, et surtout comment savoir que la workstation est réellement prête.

Il ne remplace pas le guide d'installation de Windows ni le Runbook de reprise après incident :

- [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) — installer Windows depuis zéro ;
- [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) — reconstruire la machine après panne ou réinstallation ;
- [`11_VALIDATION.md`](11_VALIDATION.md) — comprendre les preuves et les critères de validation.

---

## Résultat final attendu

Le projet est terminé lorsque l'état réel de la machine correspond aux contrats versionnés du dépôt :

```text
matériel qualifié
+ Windows 11 Pro stable et sécurisé
+ applications et réglages attendus
+ WSL2 Ubuntu 26.04 sur D:\WSL\Ubuntu-DevOps
+ projets Linux sur ext4
+ stack DevOps validée
+ VS Code / WezTerm / PowerShell cohérents
+ logs et rapports exploitables
+ sauvegarde de référence vérifiée
```

OpenClaw/OpenRouter est une intégration optionnelle et se valide séparément lorsqu'elle est utilisée.

---

## Séquence de référence

```text
comprendre
   ↓
auditer
   ↓
calculer le plan
   ↓
appliquer uniquement les écarts
   ↓
re-vérifier
   ↓
valider
   ↓
prouver l'idempotence
   ↓
sauvegarder
```

Cette séquence est plus importante que le nombre de scripts exécutés. Le projet vise une **convergence vers un état attendu**, pas une installation aveugle.

---

# Étape 1 — comprendre avant d'agir

Lire au minimum :

1. [`../README.md`](../README.md) ;
2. [`00_ARCHITECTURE.md`](00_ARCHITECTURE.md) ;
3. ce Runbook ;
4. [`11_VALIDATION.md`](11_VALIDATION.md).

La machine cible doit disposer d'une base Windows 11 Pro exploitable avec UEFI, Secure Boot, TPM, virtualisation firmware, réseau, pilotes essentiels et les volumes `C:` / `D:` correctement identifiés.

Le projet ne modifie pas automatiquement le BIOS, PBO, Curve Optimizer, la fréquence mémoire, ReBAR, le placement physique des SSD ou les firmwares.

Guides : [`02_BIOS_DRIVERS.md`](02_BIOS_DRIVERS.md), [`03_STOCKAGE.md`](03_STOCKAGE.md), [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

---

# Étape 2 — établir l'état réel

Depuis la racine du dépôt :

```powershell
.\install.ps1 -Mode Audit
```

L'audit observe la machine avant toute décision. Il collecte l'état du système, du matériel, du stockage, des applications, des réglages Windows, de WSL2, de la workstation, de Defender et des intégrations connues.

Les preuves sont conservées sous `logs\` et `reports\`. Un `RunId` permet de relier les sous-scripts d'une même exécution.

Si une anomalie apparaît, commence par le journal correspondant avant de relancer plusieurs opérations différentes.

---

# Étape 3 — calculer le plan sans modifier

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

`-PlanOnly` calcule le plan complet puis s'arrête avant l'application des changements.

Les états importants sont :

| État | Signification |
| --- | --- |
| `DÉJÀ OK` | le composant est conforme selon son validateur |
| `À FAIRE` | un écart a été détecté |
| `ACTION REQUISE` | une décision ou une preuve humaine est nécessaire |
| `IGNORE` | le composant n'est pas demandé dans cette opération |
| `ERREUR` | la conformité ne peut pas être déclarée |

Une machine partiellement prête doit produire un plan partiel. Si tout est déjà conforme, le projet doit éviter les réinstallations inutiles.

---

# Étape 4 — faire converger la workstation

Après lecture du plan :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

Le moteur vérifie chaque composant avant action, applique seulement les écarts puis re-vérifie le résultat.

Si une étape demande un redémarrage, une élévation ou une action utilisateur, traite cette action puis relance la même intention. Les composants déjà conformes doivent rester sans modification inutile.

Le détail du moteur est dans [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md).

---

# Étape 5 — vérifier WSL2

Le contrat courant impose :

```text
Distribution : Ubuntu
Release      : 26.04 / resolute
Emplacement  : D:\WSL\Ubuntu-DevOps
Filesystem   : ext4 dans le VHDX WSL2
```

Les projets DevOps Linux doivent vivre sous `~/projects`, `~/labs` ou `~/repositories`, pas sous `/mnt/c` ou `/mnt/d` comme racine quotidienne.

Le profil standard réserve **20 Go RAM**, **8 threads** et **8 Go de swap** à WSL2.

Validation ciblée :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

Guide : [`06_WSL2.md`](06_WSL2.md).

---

# Étape 6 — vérifier la stack DevOps

Installation/réparation ciblée :

```powershell
.\install.ps1 -Mode Apply -InstallDevOps -ValidateWsl -ValidateDevOps
```

La stack comprend notamment Docker, Compose, Buildx, kubectl, Helm, Minikube, kind, Terraform, Ansible, AWS CLI, GitHub CLI, Trivy et les outils qualité gérés par le dépôt.

Les versions sensibles à la reproductibilité sont définies dans `config/devops/tool-versions.env`.

Validation ciblée :

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

Guide : [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md).

---

# Étape 7 — qualifier le matériel

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

Certaines informations ne peuvent pas être déduites honnêtement par Windows. Le projet peut donc demander des preuves manuelles concernant UEFI/CSM, Above 4G, ReBAR, placement/refroidissement des SSD, stabilité mémoire, BIOS ou pilotes.

Le projet préfère `ACTION REQUISE` à un faux succès.

Guide : [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

---

# Étape 8 — intégrer OpenClaw seulement si nécessaire

L'intégration optionnelle reste sous `D:\AI\OpenClaw` et consomme le control-plane référencé par `config/openclaw/control-plane.json`.

Commande ciblée :

```powershell
.\install.ps1 -Mode Apply -InstallOpenClawAI -ValidateOpenClawAI
```

Les secrets restent hors de Git.

Guide : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

# Étape 9 — validation finale

Commande principale :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

Ajouter la qualification OpenClaw uniquement si cette intégration est utilisée.

Un `Apply` terminé n'est pas une preuve suffisante. Le projet est prêt lorsque l'état réellement observé passe les validateurs demandés.

Guide : [`11_VALIDATION.md`](11_VALIDATION.md).

---

# Étape 10 — prouver l'idempotence

Recalculer le plan :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Une workstation conforme doit tendre vers `DÉJÀ OK` pour la majorité des composants.

Si le même composant revient systématiquement en `À FAIRE`, il faut corriger la cause avant de considérer le projet terminé.

---

# Étape 11 — maintenance

Auditer d'abord :

```powershell
.\update.ps1 -Mode Audit
```

La maintenance couvre séparément Windows Update, WinGet, le runtime WSL, Ubuntu/APT, les outils DevOps épinglés et les extensions VS Code.

Guide : [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

# Étape 12 — sauvegarde de référence

Une workstation bien configurée mais non récupérable n'est pas considérée comme totalement terminée.

Le projet prévoit une sauvegarde sur un support distinct des deux SSD internes, puis une vérification de cette sauvegarde et la génération d'un plan de reprise non automatique.

Les commandes exactes et les préconditions se trouvent dans [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md) et [`21_REFERENCE_COMMANDES.md`](21_REFERENCE_COMMANDES.md).

---

## Critères de sortie

Le projet peut être déclaré prêt lorsque :

- l'audit initial est compris ;
- le plan complet est cohérent ;
- les écarts demandés ont convergé ;
- la validation Windows réussit ;
- la qualification matérielle est complète ;
- WSL2 respecte son contrat de distribution, release, stockage et filesystem ;
- la stack DevOps est qualifiée ;
- les frontières Windows/Linux sont respectées ;
- Defender, le firewall et Windows Update restent dans les garde-fous ;
- les logs et rapports permettent d'expliquer le résultat ;
- une nouvelle planification est essentiellement idempotente ;
- la sauvegarde de référence est vérifiée ;
- OpenClaw est qualifié s'il est utilisé.

Checklist : [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md).

---

## En cas d'échec

Ne contourne pas le validateur. Identifie le composant, lis son log, compare l'état observé au contrat versionné, corrige la cause puis relance le même `Verify` ou l'`Apply` ciblé.

Guide : [`22_TROUBLESHOOTING.md`](22_TROUBLESHOOTING.md).

Pour savoir quel fichier fait autorité sur chaque sujet, voir [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

Le résultat final n'est pas « le script a tourné ». Le résultat final est une **workstation DevOps/Ops reproductible, vérifiée, explicable et récupérable**.