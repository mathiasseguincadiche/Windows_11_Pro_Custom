# V11 — System Update Manager

## Objectif

`update.ps1` est le point d'entrée manuel pour maintenir la workstation Windows 11 Custom à jour sans casser les contrats V9/V10.

Le gestionnaire couvre :

- Windows Update via l'API Windows Update Agent native ;
- applications WinGet, en respectant les pins existants ;
- runtime WSL via `wsl.exe --update` ;
- Ubuntu 26.04 et dépôts APT configurés ;
- extensions VS Code Windows et WSL ;
- outils DevOps épinglés dans `config/devops/tool-versions.env`.

Il ne met jamais à jour automatiquement le BIOS, le firmware de la carte mère/GPU/SSD, ni Ubuntu vers une nouvelle release.

## Commandes

### Audit

```powershell
.\update.ps1 -Mode Audit
```

Recherche les mises à jour et affiche l'état réel. Les catalogues APT peuvent être rafraîchis afin que l'audit ne repose pas sur des métadonnées obsolètes ; aucun paquet n'est installé.

### Plan sans installation

```powershell
.\update.ps1 -Mode Apply -PlanOnly
```

Construit le plan factuel puis s'arrête avant toute installation.

### Mise à jour standard

```powershell
.\update.ps1 -Mode Apply
```

À exécuter depuis PowerShell 7 administrateur. Le script affiche le plan puis demande confirmation.

### Automatisation non interactive

```powershell
.\update.ps1 -Mode Apply -NonInteractive -Yes -NoRestartPrompt
```

Aucun redémarrage n'est déclenché automatiquement.

### Inclure les mises à jour Windows facultatives

```powershell
.\update.ps1 -Mode Apply -IncludeOptionalUpdates
```

### Inclure les pilotes Windows Update

```powershell
.\update.ps1 -Mode Apply -IncludeDrivers
```

Les pilotes sont exclus par défaut afin de ne pas remplacer aveuglément les pilotes AMD/Intel Arc ou autres pilotes validés pour la machine.

### Packages WinGet à version inconnue

```powershell
.\update.ps1 -Mode Apply -IncludeUnknownPackages
```

Les pins WinGet restent respectés. V11 n'utilise ni `--include-pinned` ni `--force`.

### Vérification finale

```powershell
.\update.ps1 -Mode Verify
```

## Ordre logique

```text
Analyse
  ↓
Windows Update
  ↓
WinGet
  ↓
WSL runtime
  ↓
Ubuntu / APT
  ↓
DevOps pinned
  ↓
VS Code extensions
  ↓
Revalidation
  ↓
Rapport + reboot requis éventuel
```

Une catégorie en échec n'empêche pas automatiquement les catégories indépendantes de continuer. Le verdict final est alors `PARTIELLEMENT À JOUR` avec la liste exacte des anomalies.

## Windows Update

Le composant utilise `Microsoft.Update.Session` et sélectionne par défaut les mises à jour logicielles non facultatives. Les mises à jour de type driver et les mises à jour `BrowseOnly` sont exclues sauf option explicite.

Le téléchargement et l'installation sont effectués via les objets Windows Update Agent, puis chaque résultat individuel est vérifié.

V11 ne redémarre pas automatiquement Windows. En mode interactif, si un redémarrage est détecté après un `Apply` réussi, l'utilisateur peut choisir explicitement de redémarrer ou de différer.

## WinGet

V11 :

1. inspecte `winget list --upgrade-available` ;
2. rafraîchit les sources pendant Apply ;
3. utilise `winget upgrade --all` ;
4. recontrôle les mises à jour restantes.

Les pins sont volontairement conservés.

## Ubuntu 26.04

Le script WSL :

- rafraîchit les index APT ;
- simule l'upgrade pour compter les paquets ;
- utilise uniquement `apt-get upgrade --with-new-pkgs` ;
- n'utilise pas `dist-upgrade`, `full-upgrade` ou `autoremove` ;
- revalide qu'aucun paquet installable ne reste.

## Outils DevOps épinglés

La source de vérité reste :

```text
config/devops/tool-versions.env
```

V11 compare l'état réel de :

- kubectl ;
- Helm ;
- Terraform ;
- AWS CLI ;
- Minikube ;
- kind.

Seuls les outils en écart sont réinstallés vers la version du dépôt. Les téléchargements disposant de checksums upstream sont validés avant installation.

Les outils gérés par APT, comme Docker, GitHub CLI, Trivy ou le terminal DevOps V10, suivent la mise à jour Ubuntu/APT.

## VS Code

Le CLI VS Code ne fournit pas un dry-run détaillé des updates d'extensions. Le composant utilise donc `code --update-extensions` pendant `Apply` pour Windows puis pour le contexte WSL. Si aucune extension n'est obsolète, la commande est sans effet.

Après l'opération, V11 revalide les ensembles d'extensions gérés par le dépôt.

## Journaux

Journal principal :

```text
logs/updates/system-update.log
```

Les sous-scripts conservent les journaux persistants gérés par le runtime V9, et le run garde :

```text
logs/runs/<RunId>/events.ndjson
logs/runs/<RunId>/summary.json
```

Rapport V11 :

```text
reports/updates/latest-run.json
```

## États attendus

```text
[DÉJÀ OK]
[À FAIRE]
[EN COURS]
[FAIT]
[IGNORÉ]
[ACTION REQUISE]
[AVERTISSEMENT]
[ERREUR]
```

## Sécurité

V11 ne doit jamais :

- contourner les pins WinGet ;
- mettre les outils DevOps à `latest` ;
- lancer un upgrade de release Ubuntu ;
- lancer `autoremove` ;
- installer les drivers/facultatives Windows sans option explicite ;
- flasher un BIOS ou firmware ;
- forcer un reboot sans choix explicite de l'utilisateur.
