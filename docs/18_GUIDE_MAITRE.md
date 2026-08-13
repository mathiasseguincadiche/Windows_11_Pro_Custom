# Guide maître — Windows 11 Pro Custom

Ce document explique le projet **Windows 11 Pro Custom** comme un tout cohérent : une workstation personnelle Windows 11 Pro, orientée DevOps/Ops, optimisée pour le matériel réel, capable d'héberger un environnement Linux complet via WSL2, de rester agréable pour les usages desktop/gaming et d'être reconstruite ou restaurée sans dépendre de réglages oubliés.

Il ne s'agit pas d'une collection de tweaks Windows ni d'un simple installateur de logiciels. Le projet applique à la workstation des principes proches de l'Infrastructure as Code : **état désiré versionné, observation de l'état réel, convergence, validation, preuves et reprise**.

Pour installer Windows depuis zéro, utiliser [`01_INSTALLATION_WINDOWS.md`](01_INSTALLATION_WINDOWS.md).

Pour une reconstruction après panne ou réinstallation, utiliser [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md).

---

# Partie I — Comprendre le projet

## 1. Ce que construit le dépôt

La machine cible remplit plusieurs rôles en même temps :

- poste Windows 11 Pro quotidien ;
- workstation DevOps/Ops ;
- plateforme Linux WSL2 ;
- environnement Docker/Kubernetes/Terraform/Ansible ;
- poste d'administration avec PowerShell 7, VS Code et WezTerm ;
- poste gaming et multimédia ;
- hôte optionnel pour OpenClaw/OpenRouter ;
- machine sauvegardable et reconstructible.

Le défi n'est pas d'installer chacun de ces outils séparément. Le défi est de garder **l'ensemble cohérent dans le temps**.

La vision du dépôt est donc :

```text
matériel réel
   ↓
Windows 11 Pro maîtrisé
   ↓
configuration versionnée
   ↓
WSL2 Linux DevOps
   ↓
applications / terminal / outils
   ↓
validation et observabilité
   ↓
sauvegarde / maintenance / reprise
```

## 2. Workstation-as-code

Le fonctionnement recherché est :

```text
état désiré versionné
        +
état réel observé
        ↓
comparaison
        ↓
plan
        ↓
action minimale
        ↓
re-vérification
        ↓
preuve
```

Cette méthode évite deux problèmes classiques :

1. **la configuration magique** — des réglages faits à la main puis oubliés ;
2. **l'installateur aveugle** — un script qui réapplique tout sans regarder l'état réel.

## 3. Principes de conception

### Machine-first

La machine réelle est observée avant toute décision.

### Idempotence

Un composant déjà conforme doit être signalé comme tel et ne pas être réinstallé inutilement.

### Réversibilité

Lorsqu'un état initial fiable peut être capturé, le dépôt prévoit un rollback.

### Sécurité conservée

La performance ne justifie pas de casser Windows Update, Defender, le firewall, Secure Boot ou les mécanismes nécessaires à WSL2.

### Matériel-aware

Le dépôt connaît la configuration cible et adapte les ressources WSL2, les contrôles et les limites à cette machine.

### Recovery-first

Une workstation bien configurée mais impossible à restaurer n'est pas considérée comme terminée.

---

# Partie II — Architecture de la workstation

## 4. Matériel cible

| Élément | Cible |
| --- | --- |
| CPU | AMD Ryzen 7 7700 — 8 cœurs / 16 threads |
| Carte mère | MSI MAG B850M Mortar WiFi |
| RAM | 48 Go DDR5 — 6000 MT/s uniquement si stable |
| GPU | Intel Arc B580 12 Go |
| SSD système | Crucial T705 PCIe 5.0 |
| SSD DATA / WSL | Crucial T705 PCIe 5.0 |
| Refroidissement | DeepCool LD240WH |
| Alimentation | Corsair RM650e 650 W |
| Boîtier | ASUS Prime AP201 |
| Affichage | 2560×1440 à haut taux de rafraîchissement |

La qualification détaillée se trouve dans [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

## 5. Stockage physique

```text
Crucial T705 #1
└── C: NTFS
    ├── Windows 11 Pro
    ├── applications Windows
    ├── drivers
    └── profil utilisateur

Crucial T705 #2
└── D: NTFS
    ├── données
    ├── D:\WSL\Ubuntu-DevOps
    ├── D:\WSL\swap\wsl-swap.vhdx
    ├── D:\AI\OpenClaw
    ├── ISO
    └── exports

Disque USB séparé
└── sauvegarde de référence
```

Aucune partition EXT4 physique n'est prévue. Ubuntu dispose de son filesystem Linux dans le VHDX WSL2 stocké sur `D:`.

Cette architecture permet de bénéficier d'un vrai filesystem Linux sans dual boot et sans transformer le second SSD en disque Linux inaccessible aux outils Windows.

## 6. Frontière Windows / Linux

La règle centrale est :

```text
Windows gère l'expérience Windows
Linux gère les workloads Linux
```

### Windows héberge

- interface graphique ;
- pilotes ;
- sécurité Windows ;
- Windows Update ;
- applications desktop ;
- PowerShell 7 ;
- VS Code UI ;
- WezTerm ;
- gaming ;
- WSL runtime ;
- sauvegarde Windows ;
- intégration OpenClaw Windows lorsque utilisée.

### Ubuntu WSL2 héberge

- Bash ;
- Git pour les projets Linux ;
- Docker Engine ;
- Compose / Buildx ;
- kubectl ;
- Helm ;
- Minikube ;
- kind ;
- Terraform ;
- Ansible ;
- AWS CLI ;
- GitHub CLI ;
- Trivy et outils qualité.

## 7. Où vivent les projets DevOps ?

Les projets actifs Linux restent dans le filesystem ext4 de WSL :

```text
/home/<user>/projects
/home/<user>/labs
/home/<user>/repositories
```

Les racines `/mnt/c` et `/mnt/d` servent à échanger avec Windows, pas à devenir l'emplacement principal de builds Linux, dépôts Git lourds ou workloads Docker.

La raison est à la fois fonctionnelle et performance : sémantique POSIX, permissions, petits fichiers, watchers et outils de build se comportent mieux dans le filesystem Linux.

---

# Partie III — Expérience quotidienne

## 8. Windows reste un vrai poste desktop

Le projet ne cherche pas à transformer Windows en terminal Linux géant.

Windows conserve :

- navigation web ;
- bureautique ;
- applications personnelles ;
- Steam et gaming ;
- multimédia ;
- pilotes graphiques ;
- gestion des périphériques ;
- interface VS Code ;
- PowerShell lorsque l'administration Windows l'exige.

La workstation doit rester agréable à utiliser même lorsque WSL2 ou Docker tourne en arrière-plan.

## 9. Terminal DevOps

WezTerm est configuré comme terminal principal avec deux univers clairement accessibles :

```text
WezTerm
├── Ubuntu / Bash DevOps  <- quotidien Linux
└── PowerShell 7          <- administration Windows
```

Le profil Bash fournit les utilitaires et complétions adaptés aux workflows DevOps.

VS Code peut ouvrir les projets directement dans WSL afin que les extensions, outils et fichiers Linux restent dans le même environnement.

## 10. VS Code et accès distants

Le poste couvre :

- VS Code + WSL ;
- Remote - SSH ;
- SFTP/FTP lorsque nécessaire ;
- Terraform ;
- Kubernetes ;
- conteneurs ;
- YAML ;
- GitHub Actions ;
- shell et qualité IaC.

Les secrets locaux, configurations de connexion personnelles et clés ne doivent pas être ajoutés dans Git.

---

# Partie IV — WSL2 et stack DevOps

## 11. Contrat WSL2

La distribution cible actuelle est Ubuntu 26.04.

Architecture :

```text
Windows 11 Pro
└── D:\WSL\Ubuntu-DevOps
    └── filesystem ext4
        └── /home/<user>
```

Le profil quotidien est dimensionné pour laisser une vraie marge à Windows :

```text
20 Go RAM
8 threads
8 Go swap
réseau mirrored
DNS tunneling
firewall actif
autoMemoryReclaim progressif
```

Un profil plus lourd est disponible pour les labs Kubernetes/builds nécessitant davantage de ressources.

Le détail complet se trouve dans [`06_WSL2.md`](06_WSL2.md), et le cours pédagogique dans [`16_WSL2_GUIDE_COMPLET.md`](16_WSL2_GUIDE_COMPLET.md).

## 12. Pourquoi ne pas donner toutes les ressources à WSL ?

Le Ryzen 7 7700 possède 16 threads et la machine 48 Go de RAM. Il serait possible de laisser WSL consommer beaucoup plus, mais ce serait un mauvais défaut pour une workstation hybride.

Le but est :

```text
assez de ressources pour Docker/Kubernetes/Terraform
+
une réserve réelle pour Windows/VS Code/navigateurs/gaming
```

Pour une grosse session de jeu lorsque Linux n'est pas nécessaire :

```powershell
wsl --shutdown
```

## 13. Stack DevOps

La distribution Linux contient les outils utiles à l'activité Ops/DevOps :

- Docker Engine, Compose, Buildx ;
- kubectl, Helm, Minikube, kind ;
- Terraform ;
- Ansible ;
- AWS CLI ;
- GitHub CLI ;
- Trivy ;
- ShellCheck ;
- shfmt ;
- terraform-docs ;
- actionlint ;
- yq ;
- TFLint.

Les outils sensibles à la reproductibilité sont versionnés par le dépôt et ne sont pas remplacés arbitrairement par `latest`.

Guide : [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md).

---

# Partie V — Windows, performance et sécurité

## 14. Philosophie d'optimisation

Le projet refuse la logique « debloat maximum ».

Il cherche plutôt :

```text
réduire le bruit inutile
+
conserver les composants nécessaires
+
mesurer avant/après
+
rendre les changements réversibles
```

Defender, Windows Update, Store, firewall, WSL/Hyper-V, mémoire compressée, pagefile, Secure Boot et TPM ne sont pas supprimés pour gagner quelques points de benchmark.

Les profils disponibles permettent d'adapter la machine au quotidien, à la confidentialité ou au gaming sans forcer tous les réglages sur tous les usages.

Guide : [`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md).

## 15. Defender

Defender reste actif.

Les exclusions suivent une politique **deny-by-default** : aucune grosse racine `C:\`, `D:\`, dossier de projets ou VHDX n'est exclue par confort.

Une exclusion doit être justifiée par une mesure réelle d'un hotspot et explicitement approuvée.

Guide : [`05_DEFENDER_PERFORMANCE.md`](05_DEFENDER_PERFORMANCE.md).

## 16. OneDrive et applications Windows

La baseline actuelle prévoit l'absence de OneDrive et gère cette décision explicitement plutôt que de laisser l'état dépendre du hasard de l'installation Windows.

Les applications automatisables sont maintenues via WinGet lorsque l'identifiant est fiable ; les autres restent manuelles.

Guide : [`08_APPLICATIONS.md`](08_APPLICATIONS.md).

---

# Partie VI — Orchestration et contrôle

## 17. install.ps1

L'orchestrateur principal sait :

- auditer ;
- planifier ;
- appliquer ;
- vérifier ;
- rollbacker lorsque c'est sûr ;
- qualifier le matériel ;
- qualifier WSL2 ;
- qualifier la stack DevOps ;
- gérer la sauvegarde ;
- intégrer les composants optionnels du dépôt.

Commandes principales :

```powershell
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Apply
.\install.ps1 -Mode Verify
.\install.ps1 -Mode Rollback
```

Installation complète :

```powershell
.\install.ps1 -Mode Apply -FullInstall
```

Prévisualisation :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Guide : [`14_ORCHESTRATION.md`](14_ORCHESTRATION.md).

## 18. Centre de contrôle

Pour l'utilisation humaine, le point d'entrée recommandé est :

```text
START_MENU.cmd
```

ou :

```powershell
.\menu.ps1
```

Le menu route installation, réparation, mises à jour, sauvegarde, audit, validation et diagnostic vers les moteurs existants.

Guide : [`17_CONTROL_CENTER.md`](17_CONTROL_CENTER.md).

---

# Partie VII — Maintenance

## 19. Gestion des mises à jour

La maintenance doit respecter la séparation entre :

```text
Windows Update
WinGet
WSL runtime
Ubuntu/APT
outils DevOps épinglés
extensions VS Code
```

Point d'entrée :

```powershell
.\update.ps1 -Mode Audit
.\update.ps1 -Mode Apply
.\update.ps1 -Mode Verify
```

Aucun reboot, flash firmware ou changement majeur Ubuntu n'est imposé silencieusement.

Guide : [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

## 20. Validation

La validation ne signifie pas « le script s'est terminé ». Elle signifie :

```text
contrat clair
+
preuve disponible
+
Verify réussi
+
action humaine traitée si nécessaire
```

Guide : [`11_VALIDATION.md`](11_VALIDATION.md).

---

# Partie VIII — Sauvegarde et reprise

## 21. Pourquoi GitHub ne suffit pas

GitHub protège le code, les configurations et la documentation. Il ne protège pas :

- l'installation Windows réelle ;
- les données de `C:` et `D:` ;
- le profil utilisateur ;
- le VHDX WSL réel ;
- les données OpenClaw ;
- les secrets locaux.

Le projet prévoit donc une vraie stratégie de sauvegarde.

## 22. Couches de protection

```text
System Restore
        ↓
rollback Windows léger

WindowsImageBackup
        ↓
C: + D: + volumes critiques

Export WSL VHDX + SHA-256
        ↓
restauration Ubuntu indépendante

GitHub
        ↓
reconstruction du socle versionné
```

La cible de sauvegarde de référence doit être un disque USB NTFS physiquement distinct des deux SSD internes.

La restauration destructrice reste une décision humaine.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

## 23. Réinstallation complète

Le Runbook décrit la reconstruction de bout en bout :

```text
média Windows
   ↓
UEFI / stockage
   ↓
Windows 11 Pro
   ↓
pilotes / Windows Update
   ↓
récupération du dépôt
   ↓
installation/convergence
   ↓
WSL2 + DevOps
   ↓
validation
   ↓
sauvegarde de référence
```

Guide : [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md).

---

# Partie IX — OpenClaw / OpenRouter

## 24. Place de l'IA dans la workstation

OpenClaw/OpenRouter est une **intégration optionnelle** de la workstation, pas son identité principale.

L'espace Windows prévu est :

```text
D:\AI\OpenClaw
```

Cette séparation évite de mélanger :

```text
D:\WSL       -> backend Linux DevOps
D:\AI        -> runtime / état OpenClaw Windows
```

Le dépôt Windows se limite à préparer et qualifier l'intégration. Le projet OpenClaw/OpenRouter conserve son propre dépôt et sa propre documentation fonctionnelle.

Guide : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

# Partie X — Sources de vérité

## 25. Ordre de confiance

Lorsqu'une information semble contradictoire :

1. état réel observé de la machine ;
2. configurations et manifests actuels ;
3. scripts actuels ;
4. documentation actuelle ;
5. changelog et historique Git.

Le changelog explique **comment le projet est arrivé ici**. Il ne doit pas devenir le mode d'emploi de la workstation.

## 26. Répertoire par responsabilité

```text
config/       état désiré et politiques
manifests/    catalogue applicatif
scripts/      mécanismes spécialisés
install.ps1   orchestration installation/convergence
update.ps1    orchestration maintenance
menu.ps1      interface humaine
logs/         journaux persistants
reports/      validations et mesures
docs/         documentation actuelle
CHANGELOG.md  historique des évolutions
```

---

# Partie XI — Ce que le projet refuse de faire

## 27. Frontières de sécurité

Le dépôt ne doit jamais automatiquement :

- formater un SSD ;
- flasher le BIOS/UEFI ;
- activer un overclocking agressif ;
- forcer une fréquence DDR5 instable ;
- désactiver Defender globalement ;
- ajouter des exclusions Defender larges non mesurées ;
- supprimer massivement des composants Windows ;
- déplacer les projets Linux actifs vers `/mnt/c` ou `/mnt/d` ;
- remplacer les versions DevOps épinglées par `latest` ;
- forcer un redémarrage ;
- exécuter automatiquement une restauration bare-metal ;
- supprimer une distribution WSL active pour faciliter un rollback ;
- stocker des secrets dans Git.

Ces limites ne sont pas des manques : elles définissent une automatisation responsable.

---

# Partie XII — Parcours recommandé

## 28. Si tu découvres le dépôt

```text
README.md
   ↓
docs/README.md
   ↓
00_ARCHITECTURE.md
   ↓
ce guide maître
```

## 29. Si tu installes la machine

```text
01_INSTALLATION_WINDOWS.md
   ↓
17_CONTROL_CENTER.md
   ↓
11_VALIDATION.md
   ↓
10_BACKUP_RESTORE.md
```

## 30. Si tu apprends WSL2

```text
16_WSL2_GUIDE_COMPLET.md
   ↓
06_WSL2.md
   ↓
07_DEVOPS_STACK.md
```

## 31. Si tu dépannes

```text
install.ps1 -Mode Audit
   ↓
logs/
   ↓
reports/
   ↓
14_ORCHESTRATION.md
   ↓
document du composant concerné
```

## 32. Si tu dois tout reconstruire

Utiliser directement [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md).

---

# Conclusion

L'essence de **Windows 11 Pro Custom** n'est ni Windows seul, ni WSL2 seul, ni les scripts PowerShell seuls.

Le projet construit une **workstation hybride maîtrisée** : Windows fournit l'expérience desktop, les pilotes, le gaming et l'administration de l'hôte ; Ubuntu WSL2 fournit l'environnement Linux DevOps ; les configurations versionnées et l'orchestration maintiennent la cohérence ; les validations empêchent les faux succès ; la sauvegarde permet de revenir d'un incident réel.

Le résultat attendu est une machine que l'on peut **comprendre, reproduire, maintenir, auditer et restaurer** sans dépendre de réglages implicites oubliés au fil du temps.
