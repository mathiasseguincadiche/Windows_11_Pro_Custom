# Politique de versionnement

Windows 11 Pro Custom utilise une seule version de produit, stockée dans le fichier racine `VERSION` au format SemVer (`MAJOR.MINOR.PATCH`).

## Règles

- `VERSION` est l’unique source de vérité de la release du projet.
- Les interfaces, journaux et rapports exposent `Release`, jamais un numéro de jalon interne de type `V24`, `V25`, `V27`, etc.
- `SchemaVersion` est réservé aux formats de données persistants ou aux contrats sérialisés. Il ne représente jamais la version du produit.
- Les composants actifs portent des noms fonctionnels stables : `storage_identity`, `storage_integrity`, `orchestration`, `menu_process_isolation`, etc.
- Les anciens chemins numérotés peuvent subsister temporairement comme wrappers de compatibilité, mais ne doivent plus être appelés par le flux normal.
- Le `CHANGELOG.md` peut conserver les anciens jalons Vxx comme historique ; ils ne définissent plus l’architecture courante.

## Release actuelle

La release courante est lue automatiquement depuis `VERSION` par le moteur d’orchestration et propagée dans les événements, les résumés d’exécution et les rapports machine.

## Compatibilité stockage

La baseline historique située sous `ProgramData\Windows11ProCustom\storage-v25` reste lisible afin de ne pas forcer un ré-enrôlement d’une machine déjà approuvée. Les nouvelles baselines utilisent `SchemaVersion = 1` et le chemin canonique `ProgramData\Windows11ProCustom\storage-identity` lorsqu’aucune baseline historique n’existe.

Aucune migration automatique ne remplace une baseline de confiance existante.
