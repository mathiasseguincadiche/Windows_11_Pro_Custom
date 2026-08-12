# Logs V9

Ce dossier est créé et alimenté automatiquement par l'orchestrateur V9. Les fichiers `.log` produits sur une vraie machine sont volontairement ignorés par Git ; seul ce document décrit le contrat.

## Arborescence

```text
logs/
├── install.log                         # chronologie synthétique de l'orchestrateur
├── bootstrap/
│   ├── 00_preflight.log
│   ├── 01_machine_state.log
│   ├── 03_apps.log
│   └── ...
├── windows/
│   ├── 10_tune.log
│   ├── 53_responsiveness_v8.log
│   └── ...
├── defender/
├── backup/
├── wsl/
│   ├── install-devops.log
│   ├── validate-devops.log
│   └── manage-vscode-extensions.log
└── runs/
    └── <run-id>/
        ├── events.ndjson
        └── summary.json
```

Chaque script possède donc **un journal persistant portant son propre nom**. Une nouvelle exécution n'efface pas l'historique : une nouvelle section séparée est ajoutée avec le `RunId`, la phase, les arguments non sensibles, la machine, l'heure de début, la sortie et le résultat final.

## Format lisible

Exemple :

```text
================================================================================================
[2026-08-12 19:30:12.123] [START] Run=20260812-193012-a1b2c3d4 Phase=Apply Script=scripts\windows\30_vscode.ps1 Args=-Mode=Apply
[2026-08-12 19:30:12.126] [HOST] Computer=DESKTOP User=mathias PowerShell=7.x
[2026-08-12 19:30:12.350] [OUTPUT] [DÉJÀ OK] settings.json déjà conforme.
[2026-08-12 19:30:13.102] [OUTPUT] [FAIT] extension ... installée et revalidée.
[2026-08-12 19:30:13.120] [END] Outcome=FAIT DurationSeconds=1.00
```

## Statuts terminaux

- `DÉJÀ OK` : la machine prouve que la cible est déjà atteinte ; aucune mutation.
- `À FAIRE` : une différence réelle a été détectée.
- `EN COURS` : une action est actuellement exécutée.
- `FAIT` : l'action a été appliquée **et revalidée**.
- `ACTION REQUISE` : une donnée ou une confirmation humaine est indispensable.
- `EN ATTENTE` : une dépendance externe/redémarrage bloque la suite.
- `AVERTISSEMENT` : information vraie mais non bloquante.
- `ERREUR` : le script ne peut pas prouver le résultat attendu.
- `IGNORE` : étape optionnelle non demandée.

## Source de vérité

Les fichiers sous `state/` servent uniquement au rollback et à l'historique. Ils ne sont jamais suffisants pour déclarer une machine conforme. À chaque relance, V9 relit Windows, WSL, WinGet, fichiers, hashes, capacités Windows, registres et autres preuves disponibles.

## Données sensibles

Les clés d'arguments ressemblant à `password`, `secret`, `token`, `credential` ou `api key` sont remplacées par `<REDACTED>` dans les logs. Les mots de passe Linux saisis pendant `adduser` sont pris directement par Linux : ils ne sont jamais passés à PowerShell comme variable ou argument et ne doivent jamais apparaître dans ces journaux.

## Rapports structurés

- `logs/runs/<run-id>/events.ndjson` : événements machine exploitables ligne par ligne.
- `logs/runs/<run-id>/summary.json` : synthèse de l'exécution.
- `reports/orchestration/latest-run.json` : dernière synthèse.
- `reports/orchestration/machine-state.json` : état factuel observé au début de la dernière exécution.
