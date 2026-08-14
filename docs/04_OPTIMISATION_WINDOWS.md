# Optimisation et réactivité Windows

## Objectif

La machine dispose de 48 Go de RAM, d'un Ryzen 7 7700, de deux SSD PCIe 5.0 et d'une Intel Arc B580. Le projet cherche à obtenir un Windows **réactif, propre et prévisible** sans casser les composants dont la workstation a réellement besoin.

L'approche n'est pas un « debloat » agressif. Elle consiste à :

```text
observer
   ↓
réduire le bruit réellement inutile
   ↓
conserver sécurité et compatibilité
   ↓
mesurer avant/après
   ↓
rollbacker si nécessaire
```

## Ce que le projet peut ajuster

Les réglages gérés couvrent notamment :

- visibilité des extensions et fichiers cachés ;
- suggestions et contenus promotionnels Windows ;
- expériences personnalisées ;
- Advertising ID ;
- Activity History ;
- Delivery Optimization sans pair-to-pair inutile ;
- Widgets / éléments d'interface ciblés ;
- options de confidentialité ;
- Game Mode et captures en arrière-plan ;
- quelques services explicitement bornés ;
- état des animations Windows et perception de réactivité ;
- comportement de lancement des applications ;
- état du pagefile et de la compression mémoire ;
- plan d'alimentation et observation du mode de puissance ;
- inventaire des applications de démarrage.

Les profils disponibles sont :

```text
standard  -> quotidien, valeur par défaut
privacy   -> réglages de confidentialité supplémentaires
gaming    -> réglages adaptés au jeu
optional  -> ajustements limités explicitement opt-in
```

Exemple :

```powershell
.\install.ps1 -Mode Apply -OptimizationProfiles standard,privacy,gaming
```

## Principes non négociables

Le dépôt ne désactive pas automatiquement :

- Windows Update ;
- Microsoft Store ;
- Microsoft Defender ;
- SmartScreen ;
- Windows Firewall ;
- Hyper-V / WSL / HNS ;
- compression mémoire ;
- fichier d'échange ;
- Secure Boot ;
- TPM ;
- Scheduled Optimize / TRIM.

Il ne supprime pas non plus des composants Windows en masse pour gagner artificiellement quelques processus.

## Réactivité Windows

Le projet distingue « réactif » de « tweak extrême ».

Les choix courants conservent :

```text
Memory Compression            active
Application Launch Prefetch   actif
Application PreLaunch         actif
pagefile                       géré par le système
crash dump                     automatique
plan d'alimentation            Balanced
mode de puissance secteur      observé, non forcé
animations Windows             conservées
TRIM / optimisation SSD        actifs
```

Cela évite les recettes populaires mais fragiles du type :

- désactiver le pagefile avec 48 Go de RAM ;
- purger agressivement la Standby List ;
- utiliser un RAM cleaner ;
- modifier HPET / BCD sans preuve ;
- désactiver core parking ou C-States globalement ;
- forcer un mode de puissance maximal en permanence ;
- supprimer des services à grande échelle ;
- lancer des benchmarks SSD d'écriture massifs.

## Gaming

La machine doit pouvoir devenir un bon poste de jeu **sans posséder un Windows spécial séparé**.

Le profil gaming peut notamment :

- conserver Game Mode ;
- réduire les captures arrière-plan ;
- éviter des réglages inutiles pendant une session ;
- fonctionner avec WSL arrêté lorsque Linux n'est pas nécessaire.

Avant une grosse session de jeu :

```powershell
wsl --shutdown
```

Cela libère les ressources de la VM WSL2 sans modifier la configuration permanente.

## Plan d'alimentation

Le plan de référence reste **Balanced**.

Pourquoi :

- Precision Boost 2 sait déjà adapter le Ryzen à la charge ;
- le poste est utilisé à la fois en desktop, DevOps et gaming ;
- un plan maximal permanent augmente consommation/chaleur sans bénéfice démontré pour tous les usages.

Le mode de puissance secteur reste observable dans les rapports, mais le profil standard ne le force pas. Windows conserve ainsi sa gestion dynamique normale au lieu d'imposer en permanence `Best Performance`.

## SSD et I/O

Les Crucial T705 sont rapides mais cela ne justifie pas des réglages d'usure inutiles.

Le projet conserve :

- TRIM ;
- Scheduled Optimize ;
- gestion Windows normale du cache ;
- surveillance de l'espace libre ;
- benchmarks légers plutôt que de gros tests d'écriture.

Un espace libre trop faible doit être traité comme un problème de capacité, pas masqué par un tweak.

## Point de restauration et rollback

Avant les modifications gérées, l'orchestrateur tente de créer un point de restauration lorsque le contexte le permet.

Il enregistre également l'état initial utile pour les composants rollbackables.

Le principe est :

```text
état avant
   ↓
Apply
   ↓
Verify
   ↓
comparaison
   ↓
Rollback possible si l'état précédent est fiable
```

Un rollback ne remplace pas une sauvegarde complète. Voir [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

## Mesure avant / après

Le dépôt produit des mesures légères pour éviter de juger la performance uniquement au ressenti.

Les rapports peuvent inclure :

- temps de démarrage / état système observable ;
- mémoire engagée ;
- pagefile ;
- MMAgent / mémoire compressée ;
- file d'attente disque ;
- plan d'alimentation ;
- comparaison avant/après.

Les fichiers de rapports sont écrits sous `reports/windows/`.

## WinUtil

WinUtil est utilisé comme **référence upstream**, pas comme script distant exécuté aveuglément.

Le dépôt maintient son propre mapping de décisions afin de savoir quels réglages sont :

```text
intégrés
optionnels
refusés
différés
```

La configuration locale reste donc contrôlée par ce dépôt.

## OneDrive

La baseline actuelle prévoit l'absence de OneDrive. Cette décision est gérée explicitement et vérifiée, plutôt que dépendre d'une désinstallation manuelle oubliée.

Elle ne signifie pas que le projet supprime arbitrairement tous les composants Microsoft.

## Defender

La sécurité et la performance Defender sont traitées séparément afin de ne pas transformer l'optimisation Windows en désactivation d'antivirus.

Voir [`05_DEFENDER_PERFORMANCE.md`](05_DEFENDER_PERFORMANCE.md).

## Vérification

Audit général :

```powershell
.\install.ps1 -Mode Audit
```

Application :

```powershell
.\install.ps1 -Mode Apply
```

Vérification :

```powershell
.\install.ps1 -Mode Verify
```

Le projet considère une optimisation réussie si les réglages attendus sont présents **et** si les garde-fous essentiels restent intacts.
