# Troubleshooting — diagnostiquer sans casser la workstation

Ce guide décrit la méthode de diagnostic du projet et les incidents les plus probables. Son principe est simple : **corriger la cause observée sans contourner les garde-fous**.

Avant toute correction, lire [`23_SOURCES_DE_VERITE.md`](23_SOURCES_DE_VERITE.md) pour savoir quel contrat fait autorité.

---

## Méthode générale

Toujours procéder dans cet ordre :

```text
1. reproduire ou observer
2. identifier le composant
3. lire le log correspondant
4. lire le contrat/version attendue
5. comparer avec l'état réel
6. corriger la cause
7. relancer le même Verify ou Apply ciblé
8. vérifier l'absence de régression
```

Évite les corrections du type « désactiver Defender », « couper le firewall », « supprimer WSL et recommencer » ou « installer latest partout » simplement pour faire disparaître un message d'erreur.

---

# 1. Où chercher les preuves

## Orchestration

```text
logs\install.log
logs\runs\<RunId>\events.ndjson
logs\runs\<RunId>\summary.json
reports\orchestration\latest-run.json
reports\orchestration\machine-state.json
```

## Mises à jour

```text
logs\updates\system-update.log
reports\updates\latest-run.json
```

## Composants

Les sous-scripts possèdent leur propre journal sous `logs\<catégorie>\` lorsqu'ils sont gérés par le moteur d'orchestration.

---

# 2. `Audit` fonctionne mais `Verify` échoue

C'est possible et normal.

`Audit` observe et décrit. `Verify` exige la conformité.

Action :

1. repérer le composant en échec ;
2. lire le détail du validateur ;
3. vérifier le fichier de configuration correspondant ;
4. lancer un `Apply` ciblé si le delta est compris ;
5. relancer `Verify`.

Ne transforme pas le mode Audit en critère de réussite.

---

# 3. Le plan veut modifier quelque chose à chaque exécution

Symptôme : après une convergence réussie, `PlanOnly` indique encore systématiquement le même composant en `À FAIRE`.

Causes possibles :

- `Verify` teste un état différent de celui produit par `Apply` ;
- un fichier est réécrit avec un contenu non stable ;
- une valeur dépend de l'environnement et change à chaque lecture ;
- une action externe annule le changement ;
- le composant a besoin d'un redémarrage avant la re-vérification.

Diagnostic : comparer le log du `Probe`, le log de l'`Apply` puis le log du `PostVerify`.

Le projet n'est pas considéré idempotent tant que cette boucle n'est pas comprise.

---

# 4. WSL est absent

Le bootstrap WSL exige que `wsl.exe` soit disponible.

Si le message indique que le runtime WSL n'est pas disponible, vérifie la préparation Windows et suis le guide [`06_WSL2.md`](06_WSL2.md).

Une fois WSL disponible, relance la même opération. Le moteur doit reprendre à partir de l'état réel et éviter de recommencer les composants déjà conformes.

---

# 5. La distribution Ubuntu existe mais n'est pas au bon emplacement

Le contrat attend :

```text
D:\WSL\Ubuntu-DevOps
```

Le script refuse de considérer conforme une distribution dont l'emplacement ne peut pas être prouvé ou ne correspond pas au contrat.

Important : le projet ne supprime pas automatiquement la distribution existante pour la recréer ailleurs.

Action :

1. conserver les données ;
2. déterminer pourquoi la distribution est ailleurs ;
3. choisir explicitement une stratégie de migration ou de reconstruction ;
4. revalider ensuite.

Pour une reconstruction complète, utiliser [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md).

---

# 6. Mauvaise release Ubuntu

Le contrat courant attend :

```text
VERSION_ID=26.04
VERSION_CODENAME=resolute
```

Une autre release est refusée par le validateur.

Le projet ne convertit pas automatiquement une distribution incompatible et ne lance pas une migration majeure d'Ubuntu pendant la maintenance ordinaire.

Traite un changement de release comme une migration contrôlée, pas comme une simple mise à jour de paquet.

---

# 7. `D:` n'est pas NTFS ou manque d'espace

WSL2 et l'intégration OpenClaw sont conçus autour du second SSD `D:` en NTFS.

Si le bootstrap refuse le volume :

- vérifier la lettre réellement attribuée ;
- vérifier le filesystem ;
- vérifier l'espace libre ;
- ne pas reformater un volume contenant des données pour satisfaire automatiquement le script.

Le stockage est une frontière d'architecture, pas un détail d'installation.

Guide : [`03_STOCKAGE.md`](03_STOCKAGE.md).

---

# 8. `.wslconfig` ne correspond pas au profil

Le validateur compare le fichier utilisateur `%USERPROFILE%\.wslconfig` au profil versionné choisi.

Si le fichier diffère :

1. vérifier quel profil a été demandé ;
2. vérifier si la modification locale était volontaire ;
3. utiliser `Apply` pour converger vers le profil souhaité ;
4. redémarrer le runtime WSL lorsque nécessaire ;
5. relancer `Verify`.

Le profil standard est celui du quotidien. Les autres profils sont des choix explicites.

---

# 9. L'utilisateur WSL n'est pas détecté ou n'est pas prêt

L'utilisateur Linux est une donnée de la distribution réelle.

Le projet peut demander une action humaine lorsque l'utilisateur doit être créé ou confirmé.

Ne place pas un mot de passe dans une option de commande, un fichier Git ou un log.

Après correction, revalide WSL2 puis la stack DevOps.

---

# 10. La stack DevOps est partiellement installée

Symptôme : certains outils sont présents, d'autres non, ou une version ne correspond pas à la cible du dépôt.

Le fichier de référence pour les outils épinglés est :

```text
config/devops/tool-versions.env
```

Action recommandée : utiliser la convergence DevOps du projet plutôt que d'installer manuellement une collection de versions différentes.

Ensuite, relancer la validation DevOps.

Guide : [`07_DEVOPS_STACK.md`](07_DEVOPS_STACK.md).

---

# 11. Docker est installé mais le validateur DevOps échoue

Docker n'est qu'une partie de la qualification.

Vérifier :

- Engine ;
- Compose ;
- Buildx ;
- service systemd ;
- utilisateur Linux ;
- autres outils demandés par la validation ;
- filesystem des projets.

Un `docker version` réussi ne suffit pas à déclarer la stack DevOps complète prête.

---

# 12. Qualification matérielle bloquée sur `ACTION REQUISE`

C'est un comportement voulu lorsque Windows ne peut pas prouver une information physique ou firmware.

Exemples : ReBAR, Above 4G, stabilité mémoire, placement physique des SSD ou vérification d'une version stable de BIOS.

Enregistre les preuves demandées de manière interactive, puis relance la validation matérielle.

Ne modifie pas le validateur pour faire disparaître la preuve manuelle.

---

# 13. Defender signale un problème de performance

Le projet utilise une politique d'exclusions deny-by-default.

Ne crée pas immédiatement une exclusion large sur `D:`, les projets, le VHDX ou le répertoire Docker.

Commence par mesurer le hotspot réel, puis n'ajoute une exclusion que si elle est justifiée et explicitement approuvée.

Guide : [`05_DEFENDER_PERFORMANCE.md`](05_DEFENDER_PERFORMANCE.md).

---

# 14. Une optimisation Windows a un effet indésirable

Les optimisations sont conçues pour rester bornées et rollbackables lorsque l'état initial est connu.

Commence par identifier le profil concerné et son état sauvegardé.

Le rollback global géré est exposé par l'orchestrateur, mais il ne remplace pas une restauration système complète.

Guide : [`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md).

---

# 15. Une mise à jour est seulement partiellement réussie

`update.ps1` traite plusieurs catégories indépendantes. Une catégorie peut échouer alors que d'autres terminent correctement.

Lire `reports\updates\latest-run.json` pour identifier les catégories en échec.

Puis corriger uniquement la cause correspondante et relancer la vérification.

Un besoin de redémarrage doit rester visible et n'est pas assimilé automatiquement à un échec.

Guide : [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

# 16. OpenClaw refuse la synchronisation du control-plane

Le bootstrap refuse d'écraser un checkout avec des modifications locales.

Si le dépôt de control-plane est marqué dirty :

1. inspecter les modifications ;
2. les conserver, commit ou sauvegarder selon leur nature ;
3. revenir à un état Git compris ;
4. relancer la synchronisation.

Ne force pas le checkout au prix de données locales non examinées.

Guide : [`19_OPENCLAW_OPENROUTER_WINDOWS.md`](19_OPENCLAW_OPENROUTER_WINDOWS.md).

---

# 17. OpenClaw est présent mais le pin ne correspond pas

La source de vérité est `config/openclaw/control-plane.json`.

Le validateur vérifie que le checkout correspond au ref approuvé lorsqu'il s'agit d'un commit explicite.

Une mise à jour du control-plane doit être qualifiée dans son propre dépôt puis référencée volontairement ici.

---

# 18. La sauvegarde ne peut pas être créée ou validée

Vérifier :

- support de sauvegarde réellement disponible ;
- capacité suffisante ;
- filesystem attendu ;
- séparation physique par rapport aux deux SSD internes ;
- état de WSL ;
- journaux du composant backup.

Ne transforme pas un disque interne contenant les données de production en « sauvegarde » uniquement pour satisfaire le contrôle.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

# 19. La CI documentation échoue

La CI documentaire vérifie notamment :

- présence des documents canoniques ;
- absence d'anciens guides versionnés dans `docs/` ;
- liens Markdown locaux ;
- cohérence des éléments importants avec le projet actuel ;
- profondeur minimale de plusieurs guides.

Une erreur documentaire doit être corrigée dans la documentation ou dans son contrat CI, pas masquée en supprimant le contrôle.

---

# 20. La CI PowerShell échoue

Le workflow qualité vérifie le parsing des scripts et PSScriptAnalyzer.

Commence par la ligne exacte signalée par le job. Ne suppose pas qu'un échec PowerShell est lié à WSL, au matériel ou au runtime si le parser pointe un fichier précis.

La CI est un garde-fou du dépôt ; la validation réelle de la workstation reste une étape distincte exécutée sur la machine cible.

---

## Quand basculer vers le Runbook de reconstruction

Utilise [`13_RUNBOOK_REINSTALLATION.md`](13_RUNBOOK_REINSTALLATION.md) lorsque le problème n'est plus une dérive de configuration mais un incident majeur : système à reconstruire, disque remplacé, installation Windows à refaire ou restauration de sauvegarde.

Pour une workstation fonctionnelle mais incohérente, commence toujours par l'audit et la convergence normale décrits dans [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md).