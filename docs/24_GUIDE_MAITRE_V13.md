# Guide maître V13 — Windows 11 Pro Custom

## Le livre du projet

Ce document explique l'ensemble du projet **Windows 11 Pro Custom** comme une workstation d'infrastructure reproductible et non comme une collection de tweaks Windows.

Il répond à quatre questions :

1. **Qu'est-ce que ce projet construit ?**
2. **Pourquoi l'architecture est-elle organisée ainsi ?**
3. **Comment l'installer, l'exploiter et le réparer sans casser sa reproductibilité ?**
4. **Où se trouve la source de vérité lorsqu'un doute apparaît ?**

Pour une installation écran par écran, utiliser [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md).

Pour une reconstruction en situation d'incident, utiliser [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md).

---

# Partie I — Comprendre le projet

## 1. Vision

La machine cible est à la fois :

- un poste Windows 11 Pro quotidien ;
- une workstation DevOps/Ops ;
- une plateforme WSL2 Linux ;
- un poste de développement/administration avec VS Code et WezTerm ;
- un environnement Docker/Kubernetes/Terraform/Ansible ;
- un hôte OpenClaw/OpenRouter ;
- un poste gaming ;
- une machine sauvegardable et reconstructible.

La difficulté n'est pas d'installer chaque logiciel séparément. La difficulté est de garder **l'ensemble cohérent**, performant, documenté et récupérable après plusieurs mois.

Le projet applique donc des principes proches de l'Infrastructure as Code :

```text
état désiré versionné
        +
état réel de la machine
        ↓
comparaison
        ↓
action minimale
        ↓
validation
        ↓
preuve
```

---

## 2. Ce que signifie « reproductible » ici

Reproductible ne signifie pas que deux PC auront exactement le même nombre de processus ou le même identifiant Windows.

Cela signifie que les éléments importants sont explicitement décrits :

- architecture de stockage ;
- matériel attendu ;
- profils Windows ;
- applications gérées ;
- distribution WSL ;
- ressources WSL ;
- outils DevOps ;
- versions sensibles ;
- configuration VS Code / WezTerm ;
- stratégie de sauvegarde ;
- stratégie de mise à jour ;
- validations et preuves.

Une reconstruction ne doit donc pas dépendre d'un souvenir du type :

> « Je crois que j'avais modifié ce réglage quelque part dans Windows il y a six mois. »

---

## 3. Les cinq principes de conception

### 3.1 Machine-first

Le script observe d'abord l'état réel.

Il ne suppose pas qu'un composant est absent uniquement parce qu'il figure dans une liste d'installation.

### 3.2 Idempotence

Une deuxième exécution sur un état déjà conforme doit tendre vers :

```text
DEJA_OK
```

et non vers une réinstallation systématique.

### 3.3 Réversibilité lorsque c'est raisonnable

Les réglages Windows versionnés possèdent des états initiaux et un rollback lorsque cela est techniquement sûr.

### 3.4 Aucun faux succès

Une commande qui a simplement retourné ne suffit pas. Les composants cherchent une preuve exploitable et revalident l'état après mutation.

### 3.5 L'automatisation s'arrête aux frontières dangereuses

Le projet refuse volontairement certaines opérations :

```text
formatage automatique       NON
flash BIOS automatique      NON
PBO/OC automatique          NON
reboot forcé                NON
bare-metal restore auto     NON
wsl --unregister auto       NON
secret dans Git             NON
```

---

# Partie II — Architecture physique et logique

## 4. Matériel cible

La source de vérité matérielle est :

```text
config/hardware/target-v5.json
```

Cible actuelle :

```text
CPU        AMD Ryzen 7 7700 — 8 cœurs / 16 threads
Carte mère MSI MAG B850M Mortar WiFi
RAM        48 Go DDR5 — cible 6000 MT/s seulement si stable
GPU        Intel Arc B580 12 Go
SSD #1     Crucial T705 PCIe 5.0
SSD #2     Crucial T705 PCIe 5.0
Écran      2560×1440, au moins ~239 Hz
Power plan Windows Balanced
```

### Pourquoi une politique hardware séparée ?

Parce qu'une machine peut démarrer tout en étant mal configurée :

- ReBAR désactivé ;
- Secure Boot désactivé ;
- mauvais SSD ;
- mémoire instable ;
- pilote GPU absent ;
- virtualisation firmware désactivée.

V5 distingue donc les faits observables depuis Windows des preuves qui nécessitent une vérification humaine.

---

## 5. Architecture stockage

```text
T705 #1
└── C: NTFS
    ├── Windows 11 Pro
    ├── logiciels Windows
    └── profils utilisateur

T705 #2
└── D: NTFS
    ├── DATA
    ├── D:\WSL\Ubuntu-DevOps
    ├── D:\WSL\swap\wsl-swap.vhdx
    ├── D:\AI\OpenClaw
    ├── ISO
    └── exports / données locales
```

### Pourquoi `D:` reste NTFS ?

WSL2 ne nécessite pas une partition Linux physique.

Ubuntu possède son filesystem ext4 **dans son VHDX** :

```text
D: NTFS
└── fichier VHDX WSL
    └── ext4 Linux
```

Avantages :

- Windows garde la maîtrise physique des deux SSD ;
- pas de dual boot ;
- pas de partition Linux à maintenir séparément ;
- sauvegarde Windows de `D:` cohérente ;
- export/import WSL disponible indépendamment.

---

## 6. Frontière Windows / Linux

Une règle simple évite beaucoup de problèmes :

```text
outil Windows -> fichiers Windows
outil Linux   -> fichiers Linux
```

### Windows héberge

- interface graphique ;
- navigateurs ;
- Office/bureautique ;
- Steam ;
- PowerShell 7 ;
- VS Code UI ;
- WezTerm ;
- OpenClaw Windows ;
- drivers ;
- Windows Update ;
- WinGet.

### Ubuntu WSL héberge

- Bash ;
- Git DevOps ;
- Docker Engine ;
- kubectl ;
- Helm ;
- Minikube / kind ;
- Terraform ;
- Ansible ;
- AWS CLI ;
- GitHub CLI ;
- outils qualité shell/IaC.

### Racines Linux autorisées

Le contrat WSL versionne :

```text
~/projects
~/labs
~/repositories
```

Les projets Linux actifs ne doivent pas vivre dans :

```text
/mnt/c
/mnt/d
```

Ce n'est pas une interdiction d'accéder aux fichiers Windows : c'est une règle sur **l'emplacement de travail principal** afin d'éviter les coûts et incompatibilités liés aux frontières de filesystem.

---

# Partie III — Les sources de vérité

## 7. Ordre de confiance

Lorsqu'il existe une ambiguïté :

```text
1. état réel de la machine
2. config/ et manifests/
3. scripts actuels
4. documentation actuelle
5. anciens exemples / anciennes captures
```

Un document ne doit jamais forcer la machine à mentir pour correspondre à une ancienne phrase.

---

## 8. `config/`

Le dossier `config/` contient les contrats et politiques structurées.

Exemples :

```text
config/
├── backup/v7-policy.json
├── defender/exclusions.approved.json
├── devops/tool-versions.env
├── hardware/target-v5.json
├── hardware/symbiosis-v5.json
├── openclaw/control-plane.json
├── orchestration/v9.json
├── updates/v11.json
├── vscode/
├── wezterm/
├── windows/v4/
├── windows/v8/
├── winutil/
└── wsl/
```

### Principe

La configuration machine-readable est préférable à une valeur uniquement écrite dans un paragraphe Markdown.

---

## 9. `manifests/`

Le manifeste applicatif WinGet actuel est :

```text
manifests/winget/apps-core.json
```

Il indique pour chaque application :

- nom ;
- identifiant WinGet ;
- installation automatique autorisée ou non.

Cela évite qu'une documentation affiche une application comme « automatique » alors que le code ne sait pas l'installer proprement.

---

## 10. `scripts/`

Les scripts spécialisés sont organisés par responsabilité :

```text
scripts/
├── backup/       -> V7
├── bootstrap/    -> installation/validation des grands composants
├── core/         -> runtime d'orchestration V9
├── defender/     -> mesure et exclusions
├── updates/      -> V11
├── windows/      -> tuning/audit/hardware/VS Code/etc.
└── wsl/          -> Linux, terminal et DevOps
```

Un utilisateur normal ne devrait pas avoir à connaître tous ces scripts pour exploiter la machine : V12 fournit le menu et V9 l'orchestrateur.

---

# Partie IV — Évolution V1 à V12

## 11. Pourquoi conserver les versions ?

Les versions documentent la progression architecturale et les invariants introduits au fil du temps.

Elles ne sont pas douze installations séparées à exécuter une par une.

Le `main` actuel contient **l'état consolidé**.

---

## 12. V1 — architecture de base

Fondations :

- Windows 11 Pro ;
- deux SSD NTFS ;
- WSL2 ;
- Defender conservé ;
- séparation Windows/Linux.

---

## 13. V2 — tuning et stack DevOps

Ajout de :

- réglages Windows contrôlés ;
- Docker/Kubernetes/Terraform/Ansible ;
- mesure Defender ;
- validation de la stack.

---

## 14. V3 — workstation DevOps

Ajout de :

- VS Code ;
- WezTerm ;
- PowerShell ;
- accès SSH/SFTP ;
- qualité IaC ;
- validations workstation.

---

## 15. V4 — Windows Optimization

Les optimisations deviennent :

- versionnées ;
- profilées ;
- réversibles ;
- mesurées avant/après.

Profils :

```text
standard
privacy
gaming
optional
```

---

## 16. V5 — Hardware Qualification

Le projet devient lié à la configuration physique réelle et refuse d'inventer les données UEFI/placement/stabilité qu'un OS ne peut pas prouver.

---

## 17. V6 — tuning WSL2

WSL2 est dimensionné pour 48 Go de RAM et le Ryzen 7 7700.

Profil standard :

```text
20 Go RAM
8 CPU logiques
8 Go swap
mirrored networking
DNS tunneling
firewall
memory reclaim gradual
sparse VHD
```

Profil lab-heavy :

```text
28 Go RAM
12 CPU logiques
12 Go swap
```

---

## 18. V7 — Backup & Disaster Recovery

Ajout d'une vraie stratégie de reprise :

```text
System Restore
+
WindowsImageBackup C: + D:
+
WSL VHDX + SHA256
+
GitHub
```

Le projet automatise la création et la vérification, mais **pas** la restauration destructive.

---

## 19. V8 — Responsiveness

Ajout de réglages de réactivité Windows contrôlés, observables et rollbackables au lieu d'un « debloat » agressif.

---

## 20. V9 — orchestration factuelle

C'est une étape architecturale majeure.

Avant V9, un bootstrap peut facilement devenir :

```text
faire A
faire B
faire C
```

V9 introduit :

```text
Discover
→ Verify
→ Plan
→ Confirm
→ Apply delta
→ Verify again
→ Persist evidence
```

Le plan entier est calculé **avant la première mutation**.

---

## 21. V10 — terminal DevOps

WezTerm devient le terminal principal, avec Ubuntu/Bash par défaut et PowerShell 7 à côté.

VS Code utilise le même environnement Bash.

Le profil fournit :

- Starship ;
- fzf ;
- zoxide ;
- CLI modernes ;
- alias/complétions DevOps.

---

## 22. V11 — mises à jour globales

La maintenance est centralisée :

```text
Windows Update
WinGet
WSL runtime
Ubuntu/APT
DevOps pinned
VS Code extensions
```

Les frontières de sécurité restent explicites.

---

## 23. V12 — centre de contrôle

Le projet devient utilisable sans mémoriser toutes les options PowerShell.

```text
START_MENU.cmd
        ↓
menu.ps1
        ↓
install.ps1 / update.ps1 / composants existants
```

Le menu est une couche de routage, pas une deuxième implémentation.

---

## 24. V13 documentation

V13 documentation ne change pas la workstation : elle consolide l'information pour qu'un débutant puisse comprendre et reconstruire l'état V12 sans devoir reconstituer l'historique du dépôt.

---

# Partie V — Installer et exploiter

## 25. Installation complète

Parcours recommandé :

```text
Windows propre
↓
Windows Update
↓
drivers AMD / Intel / MSI
↓
D: GPT + NTFS
↓
Audit du dépôt
↓
PlanOnly
↓
FullInstall
↓
reboots éventuels
↓
validation hardware / WSL / DevOps / OpenClaw
↓
Golden Backup V7
```

Voir :

- [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md) ;
- [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md).

---

## 26. Le menu V12 au quotidien

```powershell
.\menu.ps1
```

Choix typiques :

```text
Nouvelle machine          -> 1
Logiciel manquant         -> 2
Maintenance               -> 3
Snapshot validé           -> 4
Incident / rollback       -> 5
Comprendre un problème    -> 6
Confirmer la conformité   -> 7
Composant ciblé           -> 8
Lire les preuves          -> 9
```

---

## 27. Audit, Apply, Verify, Rollback

### Audit

Observe et explique.

```powershell
.\install.ps1 -Mode Audit
```

### Apply

Calcule un plan et converge uniquement les écarts.

```powershell
.\install.ps1 -Mode Apply
```

### Verify

Exige la conformité de la portée demandée.

```powershell
.\install.ps1 -Mode Verify
```

### Rollback

Restaure uniquement les états gérés et enregistrés lorsque le composant sait le faire proprement.

```powershell
.\install.ps1 -Mode Rollback
```

---

## 28. `FullInstall`

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

Active actuellement :

- installation DevOps ;
- validation DevOps ;
- validation WSL ;
- validation hardware ;
- installation OpenClaw ;
- validation OpenClaw.

Un débutant doit comprendre que **FullInstall ne veut pas dire « aucune interaction humaine »**. La qualification hardware et l'authentification d'un dépôt privé peuvent légitimement demander une action.

---

## 29. `PlanOnly`

Avant une grosse intervention :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

C'est le meilleur moyen de répondre à :

> « Qu'est-ce que le dépôt veut réellement changer sur cette machine aujourd'hui ? »

---

# Partie VI — Windows et sécurité

## 30. Optimiser sans « debloat au hasard »

Le projet évite :

- suppression massive de services ;
- scripts distants non relus ;
- désactivation de protections ;
- réglages cachés impossibles à restaurer.

Les profils Windows sont versionnés et audités.

WinUtil peut servir de référence de comparaison, mais n'est pas téléchargé puis exécuté aveuglément comme une boîte noire.

---

## 31. Defender

Principe :

```text
Defender actif
+
aucune exclusion par défaut
+
mesure
+
exception seulement si prouvée
```

Le manifeste d'exclusions est vide par défaut.

Une grosse arborescence DevOps n'obtient pas automatiquement une exclusion simplement parce qu'elle « pourrait être plus rapide ».

---

## 32. UEFI et hardware

Le code peut détecter :

- CPU ;
- RAM ;
- GPU ;
- SSD ;
- GPT ;
- Secure Boot ;
- TPM ;
- virtualisation ;
- fréquence écran ;
- drivers selon les APIs disponibles.

Il ne peut pas prouver universellement :

- le slot M.2 physique exact ;
- l'airflow ;
- la stabilité RAM sur plusieurs heures ;
- certains états UEFI spécifiques constructeur.

D'où les preuves manuelles V5.

---

# Partie VII — WSL2 et DevOps

## 33. Pourquoi WSL2 plutôt que Docker Desktop

Le projet veut une vraie base Linux DevOps avec :

```text
Ubuntu
systemd
Docker Engine
CLI Linux natives
filesystem ext4
```

Docker Desktop n'est donc pas une dépendance obligatoire du projet.

Cela réduit aussi le mélange entre deux couches de virtualisation/gestion Docker qui auraient des responsabilités concurrentes.

---

## 34. Comprendre `.wslconfig`

`.wslconfig` configure la **VM WSL globale** depuis Windows :

- RAM ;
- CPU ;
- swap ;
- réseau ;
- options expérimentales supportées.

Le dépôt versionne plusieurs profils adaptés aux cas d'usage.

Après changement :

```powershell
wsl --shutdown
```

est généralement nécessaire pour recréer la VM WSL avec la nouvelle configuration.

---

## 35. Comprendre `/etc/wsl.conf`

`/etc/wsl.conf` configure le comportement **dans la distribution** : systemd, automount et autres options Linux.

Ne confonds pas :

```text
%UserProfile%\.wslconfig  -> moteur WSL Windows
/etc/wsl.conf             -> distribution Ubuntu
```

---

## 36. Pourquoi les projets restent sur ext4

Les workloads DevOps touchent énormément de petits fichiers :

- `node_modules` ;
- Git ;
- Docker contexts ;
- Terraform modules ;
- caches ;
- builds.

En conservant les projets dans `/home`, les outils Linux travaillent nativement sur le filesystem Linux.

---

# Partie VIII — Terminal et éditeur

## 37. WezTerm

WezTerm n'est pas seulement une « jolie console » : il devient le frontend unifié vers :

```text
Ubuntu Bash
PowerShell 7
```

L'utilisateur ne doit plus se demander quel terminal Windows lancer pour chaque tâche quotidienne.

---

## 38. Bash DevOps

Le profil V10 ajoute le confort, mais ne remplace pas les commandes Unix standards de manière destructrice.

Exemple : `bat` est disponible sans rendre `cat` inutilisable.

Le démarrage Bash ne doit pas lancer des opérations réseau coûteuses : pas de `apt update`, `git fetch`, `kubectl` distant ou autre action lente automatique dans `.bashrc`.

---

## 39. VS Code

VS Code côté Windows est l'interface graphique.

Pour un projet Linux :

```bash
cd ~/projects/mon-projet
code .
```

L'extension WSL ouvre alors le projet dans le contexte Linux et le terminal intégré utilise le même Bash que WezTerm.

Remote SSH et SFTP sont disponibles pour les usages distants, mais les secrets ne doivent pas être committés.

---

# Partie IX — OpenClaw / OpenRouter

## 40. Séparation IA / DevOps

```text
Windows D:\AI\OpenClaw
-> runtime OpenClaw / state / workspace / clawops

Ubuntu WSL
-> backend DevOps Linux
```

Le control-plane OpenClaw est épinglé à un SHA Git immuable dans :

```text
config/openclaw/control-plane.json
```

Pourquoi ? Pour éviter qu'une branche `main` distante change silencieusement l'installation Windows reproductible.

---

## 41. Secrets OpenClaw/OpenRouter

Les clés API ne sont pas une configuration Git.

Elles doivent rester dans les mécanismes runtime/credential appropriés.

Une sauvegarde de `D:\AI\OpenClaw\state` doit être considérée sensible.

---

# Partie X — Sauvegarde et restauration

## 42. Reproductibilité ≠ sauvegarde

GitHub peut reconstruire les scripts et configurations, mais pas :

- tes fichiers locaux non commités ;
- l'état Windows ;
- les profils applicatifs ;
- les données OpenClaw ;
- le VHDX WSL réel.

D'où V7.

---

## 43. Les niveaux de récupération

```text
Niveau 1 : Rollback du dépôt
-> mauvais réglage géré

Niveau 2 : System Restore
-> régression Windows légère

Niveau 3 : WSL VHDX
-> Ubuntu endommagé

Niveau 4 : WindowsImageBackup
-> Windows / disque / volumes

Niveau 5 : reconstruction GitHub
-> aucune sauvegarde locale exploitable
```

---

## 44. Pourquoi restaurer WSL sous un autre nom

Remplacer immédiatement la distribution active supprime un filet de sécurité.

V7 préfère :

```text
Ubuntu
+
Ubuntu-Restore-V7
```

puis comparaison et validation.

Ce n'est qu'après preuve qu'une décision de bascule/destruction peut être prise humainement.

---

# Partie XI — Mises à jour

## 45. Pourquoi un orchestrateur V11

Une workstation hybride possède plusieurs gestionnaires de mises à jour :

```text
Windows Update
WinGet
WSL
APT
VS Code
outils téléchargés hors APT
```

Sans orchestration, il est facile d'oublier une couche ou de mettre à jour un outil DevOps épinglé vers une version non validée.

---

## 46. Règles V11

### Windows

- updates normales gérées ;
- drivers optionnels opt-in ;
- optional updates opt-in ;
- reboot jamais imposé.

### WinGet

- pins respectés ;
- pas de `--force` pour écraser la politique.

### Ubuntu

- refresh APT ;
- `upgrade --with-new-pkgs` ;
- pas de release upgrade ;
- pas d'autoremove agressif.

### DevOps

La vérité est :

```text
config/devops/tool-versions.env
```

pas « la dernière version trouvée sur Internet ».

---

# Partie XII — Observabilité

## 47. Logs persistants

V9 centralise une logique de journalisation cohérente.

Selon les composants :

```text
logs/<script>.log
logs/updates/system-update.log
logs/runs/<RunId>/events.ndjson
logs/runs/<RunId>/summary.json
```

Un log persistant permet de répondre après coup à :

- qu'a vu la machine ?
- qu'est-ce qui était déjà conforme ?
- qu'est-ce qui a changé ?
- quelle étape a échoué ?
- quelle action humaine reste à faire ?

---

## 48. Rapports

`reports/` contient les preuves structurées ou comparatives :

- préflight / état ;
- hardware ;
- benchmarks ;
- backup validation ;
- restore plan ;
- updates ;
- validations.

Les rapports sont plus adaptés aux décisions que la simple couleur verte d'une ligne terminal.

---

## 49. Vocabulaire des statuts

Les versions récentes convergent vers des états explicites :

```text
DEJA_OK          état conforme, rien à changer
A_FAIRE          écart réel détecté
EN_COURS         mutation en cours
FAIT             mutation terminée et revalidée
IGNORE           hors périmètre demandé
ACTION_REQUISE   décision/preuve humaine nécessaire
AVERTISSEMENT    condition non idéale mais explicite
ERREUR           contrat non satisfait
```

Cette terminologie évite le faux binaire « succès/échec » pour les opérations qui nécessitent réellement un humain.

---

# Partie XIII — Troubleshooting

## 50. Méthode générale

Quand quelque chose échoue :

```text
1. ne pas modifier cinq choses à la fois
2. identifier le composant exact
3. lire son log
4. relancer Audit/Verify ciblé
5. vérifier la source de vérité
6. corriger la cause
7. relancer
8. vérifier la preuve finale
```

---

## 51. Ne pas « réparer » un outil épinglé avec latest

Mauvaise réaction :

```text
Terraform pas conforme
→ télécharger latest au hasard
```

Bonne réaction :

```text
Terraform pas conforme
→ lire config/devops/tool-versions.env
→ comprendre la cible
→ utiliser le mécanisme de convergence
```

---

## 52. Ne pas contourner un hardware check

Si V5 demande une preuve manuelle, ce n'est pas un bug du script.

Le programme refuse simplement d'affirmer une information qu'il ne peut pas observer.

---

## 53. WSL semble lent

Vérifier dans cet ordre :

1. le projet est-il sur ext4 dans `/home` ?
2. le profil WSL attendu est-il actif ?
3. la RAM/swap correspondent-ils ?
4. Docker consomme-t-il anormalement ?
5. un scan Defender côté fichiers Windows est-il réellement impliqué ?
6. un processus Linux consomme-t-il CPU/I/O ?

Ne crée pas immédiatement une exclusion Defender large.

---

## 54. Windows semble lent

Comparer les preuves V4/V8 avant/après et l'état matériel.

Vérifier :

- plan Balanced ;
- températures ;
- stockage sain ;
- driver GPU ;
- tâches de fond réelles ;
- Windows Update ;
- erreurs système.

Éviter les « optimizers » tiers qui rendent le diagnostic impossible.

---

## 55. `Apply` veut refaire beaucoup de choses

Avant de valider :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Puis vérifier pourquoi les `Verify` associés considèrent les composants non conformes.

Un plan surprenant est une raison de diagnostiquer, pas de cliquer plus vite.

---

# Partie XIV — CI et qualité

## 56. Ce que GitHub Actions prouve

Les workflows vérifient selon leurs périmètres :

- syntaxe PowerShell ;
- PSScriptAnalyzer ;
- Bash/ShellCheck ;
- actionlint ;
- JSON/configuration structurée ;
- politiques destructives interdites ;
- wiring hardware/WSL/backup ;
- idempotence simulée ;
- versions épinglées ;
- menu V12 en DryRun ;
- V11 contracts.

---

## 57. Ce que la CI ne peut pas prouver

Un runner GitHub n'est pas le PC physique.

Il ne peut pas certifier :

- le BIOS réellement actif ;
- la DDR5 stable à 6000 sur plusieurs heures ;
- le vrai débit/thermique des T705 ;
- l'Arc B580 physique ;
- une vraie image de `C:` et `D:` créée sur un disque USB ;
- le rendu visuel réel de WezTerm ;
- un reboot Windows réel de la workstation.

D'où la distinction entre **contrat CI vert** et **qualification runtime réelle**.

---

# Partie XV — Exploitation courante

## 58. Routine hebdomadaire simple

Pas besoin d'exécuter toute la plateforme chaque semaine.

Une routine raisonnable :

```text
1. utiliser normalement la workstation
2. lancer V11 lorsque tu veux maintenir le système
3. surveiller les ACTION_REQUISE
4. garder Git à jour pour les projets
5. créer un nouveau backup après un changement majeur stabilisé
```

---

## 59. Avant une grosse modification

Exemples : gros update Windows, nouveau driver majeur, changement WSL, nouvelle version structurante OpenClaw.

Checklist :

```text
[ ] état actuel validé
[ ] backup récent vérifié
[ ] changement documenté
[ ] plan/rollback compris
[ ] une seule famille de changement à la fois si possible
```

---

## 60. Après une grosse modification

```powershell
.\install.ps1 -Mode Verify -ValidateHardware -ValidateWsl -ValidateDevOps
.\update.ps1 -Mode Verify
```

Si OpenClaw est concerné :

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

Puis seulement après stabilité, envisager un nouveau Golden Backup.

---

# Partie XVI — Glossaire débutant

## 61. UEFI

Firmware moderne remplaçant l'ancien BIOS legacy. Windows 11 et Secure Boot s'appuient sur cette architecture.

## 62. GPT

Table de partitions moderne utilisée pour le disque système UEFI.

## 63. Secure Boot

Mécanisme UEFI contrôlant la chaîne de démarrage autorisée.

## 64. TPM

Module de sécurité matériel/firmware utilisé notamment par Windows 11.

## 65. SVM

Nom AMD de la virtualisation CPU nécessaire à la plateforme de virtualisation/WSL2.

## 66. ReBAR

Resizable BAR : permet au CPU d'accéder plus efficacement à la mémoire GPU ; particulièrement important avec Intel Arc.

## 67. WSL2

Windows Subsystem for Linux version 2 : environnement Linux utilisant une VM légère gérée par Windows.

## 68. VHDX

Fichier disque virtuel utilisé notamment pour stocker le filesystem Linux de WSL2.

## 69. WinGet

Gestionnaire de packages/applications Windows utilisé pour les logiciels dont l'identifiant est suffisamment fiable.

## 70. APT

Gestionnaire de packages Ubuntu.

## 71. Idempotence

Propriété d'une opération qui peut être relancée sans réappliquer inutilement la même mutation lorsque l'état est déjà correct.

## 72. Rollback

Retour vers un état initial enregistré pour un réglage géré.

## 73. Bare-metal restore

Restauration d'une image système complète vers les disques/volumes depuis un environnement de récupération.

## 74. Pin

Version ou commit volontairement figé comme source de vérité afin d'éviter une mise à jour implicite non validée.

---

# Partie XVII — Antisèche

## 75. Menu

```powershell
.\menu.ps1
```

## 76. Audit global

```powershell
.\install.ps1 -Mode Audit
```

## 77. Plan complet

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

## 78. Installation complète

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

## 79. Validation complète

```powershell
.\install.ps1 -Mode Verify -ValidateHardware -ValidateWsl -ValidateDevOps -ValidateOpenClawAI
```

## 80. Rollback

```powershell
.\install.ps1 -Mode Rollback
```

## 81. Updates

```powershell
.\update.ps1 -Mode Audit
.\update.ps1 -Mode Apply
.\update.ps1 -Mode Verify
```

## 82. Backup

```powershell
.\install.ps1 -BackupAction Create -BackupTargetDrive E:
.\install.ps1 -BackupAction Verify -BackupTargetDrive E:
```

## 83. Plan de reprise

```powershell
.\install.ps1 -BackupAction RestorePlan -BackupTargetDrive E:
```

## 84. Arrêter WSL

```powershell
wsl --shutdown
```

## 85. Lister WSL

```powershell
wsl -l -v
```

---

# Partie XVIII — Carte documentaire

## 86. Pour installer

- [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md)
- [`02_BIOS_DRIVERS.md`](02_BIOS_DRIVERS.md)
- [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md)

## 87. Pour comprendre WSL/DevOps

- [`06_WSL2.md`](06_WSL2.md)
- [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md)
- [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md)
- [`17_WSL2_TUNING_V6.md`](17_WSL2_TUNING_V6.md)

## 88. Pour comprendre Windows/hardware

- [`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md)
- [`05_DEFENDER_PERFORMANCE.md`](05_DEFENDER_PERFORMANCE.md)
- [`14_WINDOWS_OPTIMIZATION_V4.md`](14_WINDOWS_OPTIMIZATION_V4.md)
- [`15_HARDWARE_QUALIFICATION_V5.md`](15_HARDWARE_QUALIFICATION_V5.md)
- [`20_WINDOWS_RESPONSIVENESS_V8.md`](20_WINDOWS_RESPONSIVENESS_V8.md)

## 89. Pour sauvegarder/restaurer

- [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md)
- [`18_BACKUP_DISASTER_RECOVERY_V7.md`](18_BACKUP_DISASTER_RECOVERY_V7.md)

## 90. Pour les versions récentes

- [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md)
- [`21_ORCHESTRATION_IDEMPOTENCE_V9.md`](21_ORCHESTRATION_IDEMPOTENCE_V9.md)
- [`21_DEVOPS_TERMINAL_V10.md`](21_DEVOPS_TERMINAL_V10.md)
- [`22_SYSTEM_UPDATE_MANAGER_V11.md`](22_SYSTEM_UPDATE_MANAGER_V11.md)
- [`23_INTERACTIVE_CONTROL_CENTER_V12.md`](23_INTERACTIVE_CONTROL_CENTER_V12.md)

---

# Conclusion

Le projet est conçu autour d'une idée simple : **une workstation importante doit pouvoir être comprise, vérifiée et reconstruite**.

La réussite n'est donc pas seulement :

```text
« Windows démarre »
```

mais :

```text
Windows démarre
+
le matériel attendu est qualifié
+
les réglages sont explicites
+
WSL/DevOps fonctionnent dans leur bonne frontière
+
les versions critiques sont maîtrisées
+
les changements sont observables
+
la machine peut être mise à jour
+
la machine peut être sauvegardée
+
la reprise est documentée
+
les actions dangereuses restent humaines
```

C'est ce qui transforme ce dépôt d'une liste de scripts personnels en **procédure reproductible de gestion d'une workstation Windows/DevOps**.
