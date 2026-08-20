# Guide de prise en main — comprendre la workstation avant de l'utiliser

Ce document remplace le rôle d'une simple **vue consolidée** : il sert de passerelle pédagogique entre le [`README`](../README.md) et les guides techniques.

Il explique les concepts indispensables avant d'exécuter le [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).

## 1. Workstation-as-code

Une workstation-as-code est un poste dont les règles importantes sont décrites dans des fichiers versionnés et vérifiables.

```text
état réel
   ↓
contrat attendu
   ↓
écart mesuré
   ↓
correction
   ↓
nouvelle vérification
```

Le fait qu'un script ait déjà été exécuté ne prouve pas que la machine est encore conforme.

## 2. Pourquoi Windows + WSL2 ?

```text
Windows
├── desktop, sécurité, pilotes
├── PowerShell 7
├── VS Code
└── Windows Terminal
    ├── PowerShell 7 - DevOps
    └── Ubuntu - DevOps

WSL2 Ubuntu 26.04
├── Bash
├── Docker / Kubernetes
├── Terraform / Ansible / AWS
└── projets Linux sur ext4
```

Windows reste l'hôte. Ubuntu fournit le backend Linux DevOps. Windows Terminal ouvre les bons contextes mais ne remplace pas Bash.

## 3. Audit, PlanOnly, Apply, Verify et Rollback

| Intention | Sens |
| --- | --- |
| `Audit` | observer et décrire |
| `PlanOnly` | calculer ce qui serait modifié |
| `Apply` | corriger les écarts |
| `Verify` | exiger la conformité |
| `Rollback` | restaurer certains réglages gérés lorsqu'un état initial existe |

Un `Audit` peut réussir alors qu'un `Verify` échoue : l'audit a correctement observé un écart, tandis que la vérification refuse de déclarer la machine conforme.

## 4. Idempotence

Une opération idempotente peut être relancée sans réappliquer inutilement ce qui est déjà correct.

```text
premier PlanOnly  -> éléments À FAIRE
Apply             -> correction
Verify            -> conformité
second PlanOnly   -> tendance vers DÉJÀ OK
```

Un composant toujours `À FAIRE` doit être diagnostiqué plutôt que réinstallé aveuglément.

## 5. Source de vérité

Une source de vérité possède la valeur de référence.

```text
config/       -> contrats déclaratifs
manifests/    -> catalogues
scripts/      -> comportement d'implémentation
état machine  -> réalité observée
docs/         -> explication du contrat
```

La documentation ne doit pas créer un second contrat contradictoire. Voir [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md).

## 6. Pourquoi `C:` et `E:` sont sensibles

La workstation utilise deux SSD de même famille. Une lettre de lecteur ne suffit pas toujours à prouver l'identité physique.

Le parcours d’identité stockage enrôle puis vérifie :

```text
C: -> Windows
E: -> données / WSL2
```

Première qualification :

```powershell
.\scripts\bootstrap\00_storage_identity.ps1 -Mode Audit
.\scripts\bootstrap\00_storage_identity.ps1 `
  -Mode Record `
  -ConfirmHealthyTopology
.\scripts\bootstrap\00_storage_identity.ps1 -Mode Verify
```

`Record` ne doit être utilisé qu'après contrôle humain d'une topologie saine. Une alerte inexpliquée ne se résout pas en remplaçant la baseline.

Référence : [`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md).

## 7. Baseline et drift

Une **baseline** est un état de référence explicitement approuvé.

Une **dérive** (`drift`) est une différence entre cette référence et l'état observé plus tard. Elle peut être légitime ou problématique ; elle doit être expliquée avant de modifier la baseline.

## 8. STATIC, SIMULATED et PHYSICAL

- `STATIC` : cohérence du code, des contrats et des workflows ;
- `SIMULATED` : comportement exercé sans prétendre représenter toute la machine physique ;
- `PHYSICAL` : preuve produite sur la workstation réelle avec les confirmations nécessaires.

Une CI verte ne prouve pas l'état du BIOS, des SSD, du refroidissement ou de la stabilité RAM.

Voir [`26_PREUVES_DRIFT_ET_RESTAURATION.md`](26_PREUVES_DRIFT_ET_RESTAURATION.md).

## 9. Ce que le projet automatise

Le dépôt peut auditer, converger et valider Windows, WSL2, la stack DevOps et Windows Terminal. Il peut aussi produire des preuves, gérer des sauvegardes et détecter une dérive.

## 10. Ce qui reste humain

Le dépôt ne doit pas automatiser aveuglément :

- le choix d'un disque ambigu ;
- un formatage destructif ;
- un flash BIOS ;
- un overclocking ;
- la saisie de secrets ;
- une restauration bare-metal ;
- une preuve physique non observable.

Le bon comportement est alors `ACTION REQUISE`.

## 11. Frontière OpenClaw/OpenRouter

`Windows_11_Pro_Custom` ne possède pas OpenClaw/OpenRouter. Le projet IA est géré séparément dans `mathiasseguincadiche/openclaw_openrouter`.

La présence d'un projet externe sur la workstation ne l'intègre pas au verdict de conformité Windows/WSL2/DevOps.

## 12. Document suivant

```text
Architecture
→ 00_ARCHITECTURE.md

WSL2 pour débutant
→ 16_WSL2_GUIDE_COMPLET.md

Parcours normal
→ 20_RUNBOOK_OPERATIONNEL.md

Commande exacte
→ 21_REFERENCE_COMMANDES.md

Problème
→ 22_TROUBLESHOOTING.md

Reconstruction
→ 13_RUNBOOK_REINSTALLATION.md

Fin du projet
→ 24_CRITERES_ACCEPTATION.md
```

Pour un terme inconnu, utilisez [`GLOSSAIRE.md`](GLOSSAIRE.md).

À retenir : **le projet ne cherche pas à prouver qu'un script a tourné ; il cherche à prouver que la workstation réelle respecte ses contrats.**
