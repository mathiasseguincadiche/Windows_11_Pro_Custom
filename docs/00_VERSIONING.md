# Politique de versionnement

Windows 11 Pro Custom utilise une seule version de produit, stockée dans le fichier racine `VERSION` au format SemVer (`MAJOR.MINOR.PATCH`).

## Règles

- `VERSION` est l’unique source de vérité de la release du projet.
- Les interfaces, journaux et rapports exposent `Release`, jamais un ancien numéro de jalon de développement.
- `SchemaVersion` est réservé aux formats de données persistants ou aux contrats sérialisés. Il ne représente jamais la version du produit.
- Les composants actifs portent des noms fonctionnels stables : `storage_identity`, `storage_integrity`, `orchestration`, `menu_process_isolation`, etc.
- Les anciens formats de données peuvent rester lisibles pour préserver une baseline ou une sauvegarde déjà approuvée, mais aucun ancien nom de composant n’est utilisé par le flux normal.
- `CHANGELOG.md` et l’historique Git conservent la chronologie des anciens jalons ; ils ne définissent plus l’architecture courante.

## Release actuelle

La release courante est lue automatiquement depuis `VERSION` par le moteur d’orchestration et propagée dans les événements, les résumés d’exécution et les rapports machine.

## Compatibilité des données persistantes

Une baseline historique déjà approuvée peut être lue depuis son ancien emplacement sous `ProgramData\Windows11ProCustom\storage-v25`. Les nouvelles baselines utilisent `SchemaVersion = 1` et le chemin canonique `ProgramData\Windows11ProCustom\storage-identity` lorsqu’aucune baseline historique n’existe.

Cette compatibilité est uniquement une **lecture de données existantes** : elle ne réintroduit pas d’ancien composant dans l’architecture active et ne déclenche jamais de remplacement automatique d’une baseline de confiance.
