# Validation — prouver que la workstation est réellement prête

La validation est l'étape qui transforme une installation en **résultat démontré**.

Le projet ne considère jamais qu'une machine est conforme uniquement parce qu'une commande s'est terminée sans erreur visible. La conformité doit être prouvée par l'état réel observé, les contrats versionnés, les validateurs et les preuves générées.

Le modèle est :

```text
contrat attendu
      +
état réel observé
      +
preuve disponible
      ↓
Verify réussi
      ↓
critère d'acceptation rempli
```

Le Runbook de réalisation est [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md). La checklist de sortie est [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md).

---

## 1. Audit, Apply et Verify ne veulent pas dire la même chose

### Audit

```powershell
.\install.ps1 -Mode Audit
```

L'audit observe et décrit. Il peut révéler un écart sans interrompre toute l'exécution.

### Apply

```powershell
.\install.ps1 -Mode Apply
```

`Apply` cherche à faire converger les composants demandés vers leur état attendu. Il s'appuie sur un `Verify` préalable pour ne modifier que les écarts.

### Verify

```powershell
.\install.ps1 -Mode Verify
```

`Verify` exige la conformité des composants qu'il contrôle. C'est le mode qui sert à décider si un état peut être considéré prêt.

La séquence correcte est donc :

```text
Audit -> comprendre
Plan  -> prévoir
Apply -> corriger
Verify -> prouver
```

---

## 2. Validation de base

Commande :

```powershell
.\install.ps1 -Mode Verify
```

Elle vérifie les composants de base prévus par l'orchestrateur : applications, réglages Windows, WSL2 selon le périmètre courant, workstation et contrats Windows associés.

Pour une qualification de projet complète, ajouter les validateurs spécialisés.

---

## 3. Qualification matérielle

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

La qualification matérielle combine deux types de preuve.

### Preuves observables automatiquement

Le projet peut vérifier notamment :

- CPU ;
- quantité de mémoire ;
- carte mère ;
- GPU ;
- présence et état des SSD ;
- GPT ;
- Secure Boot ;
- TPM ;
- virtualisation firmware ;
- éléments réseau et stockage observables.

### Preuves manuelles

Certaines informations ne peuvent pas être déduites honnêtement depuis Windows :

- état UEFI/CSM ;
- Above 4G ;
- Resizable BAR ;
- placement physique des SSD ;
- refroidissement ;
- stabilité mémoire ;
- revue du BIOS ;
- revue des pilotes constructeur.

Le projet signale alors `ACTION REQUISE` au lieu d'inventer un succès.

Guide : [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

---

## 4. Qualification WSL2

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

Le contrat WSL2 courant exige notamment :

```text
Distribution : Ubuntu
Release      : 26.04 / resolute
Mode         : WSL2
Emplacement  : D:\WSL\Ubuntu-DevOps
HOME         : filesystem Linux ext4
```

Le validateur doit également confirmer les éléments runtime prévus par le projet : ressources du profil, systemd, stockage et workspaces Linux.

Une distribution qui existe mais se trouve au mauvais emplacement n'est pas considérée conforme simplement parce qu'elle démarre.

Guide : [`06_WSL2.md`](06_WSL2.md).

---

## 5. Qualification DevOps

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

Cette validation ne se limite pas à Docker.

Elle contrôle la stack prévue par le projet : Docker/Compose/Buildx, Kubernetes CLI, Helm, Minikube/kind, Terraform, Ansible, AWS CLI, GitHub CLI, outils qualité et versions explicitement épinglées.

Les cibles reproductibles sont définies dans :

```text
config/devops/tool-versions.env
```

Une commande individuelle réussie ne remplace pas la qualification globale du composant.

Guide : [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md).

---

## 6. Qualification OpenClaw/OpenRouter

Uniquement si l'intégration IA fait partie de la workstation :

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

Le validateur vérifie le control-plane approuvé, l'installation Windows et le backend WSL2 DevOps attendu par l'intégration.

La qualification OpenClaw reste séparée de la qualification générale afin que la workstation Windows/DevOps ne dépende pas obligatoirement de cette extension.

Guide : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

## 7. Commande de qualification principale

Pour la workstation DevOps/Ops complète :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

Si OpenClaw est utilisé, exécuter également sa qualification dédiée.

Le résultat attendu est l'absence d'écart critique non traité et la présence des preuves manuelles nécessaires.

---

## 8. Les statuts doivent être interprétés correctement

| Statut | Interprétation |
| --- | --- |
| `DÉJÀ OK` | aucune modification nécessaire |
| `FAIT` | une modification a été appliquée |
| `OK` | vérification réussie |
| `À FAIRE` | un écart existe |
| `ACTION REQUISE` | une décision ou une preuve humaine manque |
| `AVERTISSEMENT` | situation non bloquante à comprendre |
| `IGNORE` | hors périmètre de l'opération |
| `ERREUR` | la conformité ne peut pas être déclarée |

Un `FAIT` n'est pas équivalent à `OK` : après une modification, la re-vérification doit confirmer que la cible est réellement conforme.

---

## 9. Logs et rapports de preuve

Le moteur conserve des preuves persistantes :

```text
logs\install.log
logs\<catégorie>\<script>.log
logs\runs\<RunId>\events.ndjson
logs\runs\<RunId>\summary.json
reports\orchestration\latest-run.json
reports\orchestration\machine-state.json
```

D'autres composants génèrent leurs propres rapports sous `reports\`.

Le `RunId` permet de relier les étapes d'une même exécution et d'éviter de mélanger des preuves produites à des moments différents.

---

## 10. Un ancien rapport n'est pas une preuve actuelle

Exemple : un rapport indiquant hier que WSL2 était conforme ne prouve rien après une modification de `.wslconfig`, une mise à jour du runtime ou une migration de fichiers.

La conformité est toujours recalculée à partir de l'état actuel.

Cette règle est détaillée dans [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

---

## 11. Idempotence comme preuve supplémentaire

Après une convergence réussie, recalculer le plan :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Le résultat doit tendre vers `DÉJÀ OK`.

Si le même composant revient systématiquement en `À FAIRE`, il existe une incohérence entre détection, état attendu et Apply. Cette boucle doit être corrigée avant de considérer le composant stable.

L'idempotence est donc un critère d'acceptation du projet, pas seulement une propriété théorique du code.

---

## 12. Validation après mise à jour

Le gestionnaire de maintenance possède ses propres modes :

```powershell
.\update.ps1 -Mode Audit
.\update.ps1 -Mode Apply
.\update.ps1 -Mode Verify
```

Après une maintenance structurante, il est pertinent de requalifier les domaines concernés avec `install.ps1 -Mode Verify`.

Exemples :

- changement du runtime WSL -> revalider WSL2 ;
- modification d'un outil épinglé -> revalider DevOps ;
- mise à jour importante de pilotes -> revalider le matériel et le système.

Guide : [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

## 13. Validation et sauvegarde

La dernière étape du projet n'est pas uniquement la conformité runtime. La stratégie de reprise doit elle aussi être exploitable.

Une fois la machine stabilisée :

1. créer ou actualiser la sauvegarde de référence selon la politique ;
2. vérifier cette sauvegarde ;
3. confirmer qu'un plan de reprise peut être préparé.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

## 14. Ce que la validation ne doit jamais masquer

Un verdict positif ne doit pas être obtenu en :

- ignorant un composant demandé ;
- remplaçant une preuve matérielle par une supposition ;
- modifiant le contrat uniquement pour faire passer l'état actuel ;
- considérant une CI verte comme preuve du matériel réel ;
- utilisant un ancien fichier `state/` comme preuve de conformité ;
- désactivant une protection système pour faire disparaître un échec.

Le validateur doit représenter la vérité du projet, pas produire un résultat vert à tout prix.

---

# Critères d'acceptation finaux

La validation technique est complète lorsque :

```text
Verify de base réussi
+
qualification matérielle réussie
+
WSL2 conforme
+
stack DevOps conforme
+
actions humaines closes
+
idempotence cohérente
+
preuves disponibles
+
sauvegarde vérifiée
```

OpenClaw s'ajoute uniquement lorsqu'il fait partie du périmètre réel de la workstation.

La checklist détaillée et réutilisable est [`24_CRITERES_ACCEPTATION.md`](24_CRITERES_ACCEPTATION.md).

Le projet peut alors être considéré non seulement **installé**, mais **validé**.