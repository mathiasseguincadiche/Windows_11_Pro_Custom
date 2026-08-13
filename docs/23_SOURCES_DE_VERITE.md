# Sources de vérité du projet

Cette page définit la hiérarchie utilisée pour résoudre les divergences entre l’état réel de la machine, les contrats versionnés, les scripts, les rapports et la documentation.

Le principe est :

```text
état réel observé
        +
contrat versionné actuel
        ↓
validation
```

Un ancien rapport, un ancien commit ou un souvenir de configuration ne remplace jamais l’état actuel.

---

## Hiérarchie générale

En cas de divergence, raisonner dans cet ordre :

1. **état réel de la machine** — ce qui existe maintenant ;
2. **configurations et manifests actuels** — ce que le projet attend ;
3. **scripts et validateurs actuels** — comment le projet observe et converge ;
4. **documentation active** — explication humaine du présent ;
5. **logs et rapports** — preuve d’une exécution donnée ;
6. **CHANGELOG et historique Git** — historique uniquement.

Si la documentation diverge du comportement actuel, la divergence est un bug documentaire à corriger.

---

# Racine du dépôt

| Fichier | Responsabilité |
| --- | --- |
| `README.md` | vitrine, objectif, architecture résumée et parcours de démarrage |
| `install.ps1` | audit, planification, convergence, validation et rollback géré |
| `update.ps1` | maintenance de Windows, WinGet, WSL, Ubuntu, DevOps et VS Code |
| `menu.ps1` | interface humaine au-dessus des orchestrateurs |
| `START_MENU.cmd` | lancement simple du centre de contrôle |
| `CHANGELOG.md` | historique des évolutions |

Le README explique le projet. Les détails opérationnels vivent dans `docs/`.

---

# `config/` — contrats machine-readable

## WSL2

`config/wsl/runtime-contract.json` définit notamment :

- la distribution `Ubuntu` ;
- la release `26.04` / `resolute` ;
- l’emplacement `D:\WSL\Ubuntu-DevOps` ;
- le filesystem Linux attendu ;
- les racines de travail `~/projects`, `~/labs`, `~/repositories` ;
- les racines Windows qui ne doivent pas devenir les workspaces Linux principaux.

Les fichiers `config/wsl/*.wslconfig` définissent les profils de ressources et de réseau.

## DevOps

`config/devops/tool-versions.env` définit les versions explicitement épinglées des outils sensibles à la reproductibilité.

Une release plus récente disponible sur Internet n’annule pas automatiquement cette cible.

## Terminal WezTerm

`config/wezterm/wezterm.lua` est la source de vérité du terminal géré par le projet.

Le contrat courant impose :

```text
Ubuntu DevOps (WSL2)          -> profil par défaut
PowerShell 7                  -> administration Windows
OpenClaw / clawops (Windows)  -> CLI IA Windows-native
```

`scripts/windows/31_wezterm.ps1` valide ce contrat puis compare par SHA256 la configuration versionnée avec `%USERPROFILE%\.wezterm.lua`.

La présence du profil OpenClaw dans WezTerm ne signifie pas qu’OpenClaw est installé : l’installation et la qualification du runtime restent la responsabilité de l’intégration OpenClaw.

## Matériel

`config/hardware/` décrit la machine cible et les critères de qualification. Ces fichiers servent à **observer et valider**, pas à deviner un état physique absent.

## Windows et Defender

`config/windows/` contient les politiques structurées des réglages gérés. `config/defender/` contient la politique d’exclusions approuvées.

## Sauvegarde

`config/backup/` décrit la politique de sauvegarde et les limites de la reprise automatisable.

## OpenClaw

`config/openclaw/control-plane.json` définit le dépôt et le ref approuvé du control-plane consommé par l’intégration Windows.

Le runtime OpenClaw, `clawops`, leurs versions et leur logique fonctionnelle restent gouvernés par le control-plane `openclaw_openrouter`. Le dépôt Windows ne doit pas recopier ces contrats dans WezTerm.

Les noms de certains fichiers internes conservent des identifiants techniques hérités lorsqu’ils font partie du contrat actuel. La documentation active, elle, reste organisée par responsabilité et non par ancienne version du projet.

---

# `manifests/` — catalogues déclaratifs

Les manifests décrivent les éléments attendus qui se prêtent à une représentation structurée, notamment les applications Windows et les packages WinGet.

Le manifest exprime l’intention ; le script d’installation reste responsable de vérifier si cette intention est réellement automatisable dans le contexte courant.

---

# `scripts/` — implémentation

Organisation principale :

```text
scripts/core/
scripts/bootstrap/
scripts/windows/
scripts/wsl/
scripts/updates/
scripts/backup/
scripts/defender/
```

- `core` : moteur partagé, statuts, logs, probes et re-vérification ;
- `bootstrap` : composition des grandes briques de la workstation ;
- `windows` : réglages, audits, terminal, matériel et mesures Windows ;
- `wsl` : environnement Linux et stack DevOps ;
- `updates` : maintenance par domaine ;
- `backup` : sauvegarde, validation et préparation de reprise ;
- `defender` : politique Defender gérée.

Tous les scripts ne sont pas des points d’entrée destinés à l’utilisateur. Les interfaces normales restent `menu.ps1`, `install.ps1` et `update.ps1`.

---

# `logs/`, `reports/` et `state/`

## Logs

Ils expliquent ce qui s’est produit pendant une exécution.

## Reports

Ils fournissent des preuves structurées : machine-state, validation, maintenance, mesures, etc.

## State

Il conserve certains états initiaux nécessaires au rollback de réglages gérés.

**Aucun de ces trois emplacements ne prouve à lui seul la conformité actuelle de la machine.** La conformité vient d’une nouvelle observation et d’un `Verify` réussi.

---

# `docs/` — documentation technique officielle

La documentation active doit :

- décrire l’état actuel ;
- correspondre aux paramètres et comportements réellement disponibles ;
- distinguer action automatique, validation et action humaine ;
- distinguer réalisation normale et reconstruction après incident ;
- expliquer les résultats attendus ;
- éviter de raconter l’historique à la place du fonctionnement présent.

L’historique appartient à `CHANGELOG.md` et à Git.

---

# GitHub Actions — non-régression

Les workflows du dépôt contrôlent notamment :

- PowerShell et Bash ;
- configuration structurée et syntaxe WezTerm ;
- frontières de sécurité ;
- runtime WSL ;
- orchestration et idempotence ;
- matériel ;
- réactivité Windows ;
- baseline OneDrive ;
- terminal DevOps ;
- maintenance ;
- centre de contrôle ;
- documentation ;
- runtime smoke.

Une CI verte prouve les contrats automatisables du dépôt. Elle ne remplace pas la qualification réelle du matériel et de la workstation cible.

---

## Résoudre une divergence

Si la documentation dit A mais que le contrat et le validateur actuels disent B :

1. confirmer l’état réel ;
2. confirmer que B représente bien l’intention actuelle ;
3. corriger la documentation ;
4. renforcer le contrôle documentaire si la dérive peut revenir.

Si le code fait B mais que le projet doit réellement faire A, il s’agit d’une modification fonctionnelle, pas d’une correction de documentation.

---

## Résumé

```text
MACHINE RÉELLE     -> vérité observée
CONFIG / MANIFESTS -> état attendu
SCRIPTS             -> observation et convergence
VERIFY              -> décision de conformité
LOGS / REPORTS      -> preuves d’exécution
DOCS                -> explication officielle
CHANGELOG / GIT     -> historique
```

Cette hiérarchie permet au projet de rester compréhensible et maintenable sans confondre le présent avec les étapes qui ont conduit à son état actuel.