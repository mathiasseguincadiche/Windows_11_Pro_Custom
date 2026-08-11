# Windows Optimization V4

## Objectif

La V4 transforme les idées utiles de WinUtil en une configuration locale, versionnée, vérifiable et réversible pour ce poste Windows 11 Pro DevOps/Ops.

WinUtil reste une référence upstream. Le dépôt ne lance pas automatiquement `irm ... | iex` et ne délègue pas son état système à un preset externe qui peut évoluer.

## Profils

### `standard` — par défaut

Profil quotidien appliqué automatiquement avec `install.ps1`.

Il ajoute à la couche V2/V3 :

- Activity History désactivé ;
- publication et upload des activités utilisateur désactivés ;
- exécution WPBT désactivée ;
- Delivery Optimization limité au téléchargement HTTP sans partage peer-to-peer ;
- `End Task` disponible au clic droit dans la barre des tâches.

Les réglages déjà présents dans `scripts/windows/10_tune.ps1` restent actifs : Consumer Features, Advertising ID, suggestions, expériences personnalisées et télémétrie au niveau requis.

### `privacy` — optionnel

```powershell
.\install.ps1 -Mode Apply -OptimizationProfiles standard,privacy
```

Ajoute :

- localisation système refusée ;
- capteur de localisation désactivé ;
- mise à jour automatique Maps liée à la localisation désactivée ;
- service `lfsvc` configuré en Disabled ;
- téléchargements de métadonnées pour applications compagnons de périphériques bloqués.

Ce profil peut affecter météo, cartes, localisation et fonctions associées. Il n'est donc jamais appliqué implicitement.

### `gaming` — optionnel

```powershell
.\install.ps1 -Mode Apply -OptimizationProfiles standard,gaming
```

- Game Mode activé ;
- captures Game DVR désactivées ;
- captures en arrière-plan désactivées.

Le profil ne touche pas HAGS, VRR, HDR, ReBAR, pilotes Intel Arc ou paramètres de latence Registry non documentés.

### `optional` — optionnel

```powershell
.\install.ps1 -Mode Apply -OptimizationProfiles standard,optional
```

Tuning services volontairement limité :

- `DiagTrack` : Disabled ;
- `MapsBroker` : Manual.

Sont explicitement exclus :

- `SharedAccess` ;
- `StorSvc` ;
- Windows Update ;
- Defender ;
- Firewall ;
- HNS / Hyper-V / WSL.

## Mapping WinUtil

Le fichier :

```text
config/winutil/mathias-winutil.json
```

trace chaque décision WinUtil → V4.

Il s'agit d'un **fichier de référence du projet**, pas d'un export WinUtil présenté comme directement importable.

### Intégrés nativement

- `WPFTweaksActivity` ;
- `WPFTweaksConsumerFeatures` ;
- `WPFTweaksWPBT` ;
- `WPFTweaksTelemetry` ;
- `WPFTweaksDeliveryOptimization` ;
- `WPFTweaksEndTaskOnTaskbar` ;
- `WPFTweaksRestorePoint`.

### Optionnels

- `WPFTweaksLocation` ;
- sous-ensemble prudent de `WPFTweaksServices`.

### Non automatisés

- Disk Cleanup ;
- suppression des fichiers temporaires.

Ces opérations suppriment des données et ne possèdent pas de rollback réel. Elles restent séparées du moteur V4 réversible.

### Refusés par défaut

- suppression de OneDrive ;
- suppression de Windows AI / Copilot / packages ;
- désactivation Reserved Storage ;
- suppression Edge ;
- tweaks visuels « Best Performance » ;
- modifications services en masse.

## Restore point + backup

Avant `Apply`, la V4 tente de créer un point de restauration Windows :

```text
Windows_11_Pro_Custom V4 before optimization
```

Chaque profil sauvegarde aussi son état initial sous :

```text
state/windows-v4/<profile>.before.json
```

Cette sauvegarde initiale n'est jamais écrasée par un second Apply.

## Benchmark avant / après

La V4 crée :

```text
reports/windows/v4-benchmark-before.json
reports/windows/v4-benchmark-after.json
reports/windows/v4-benchmark-comparison.json
```

Le snapshot mesure notamment :

- processus ;
- processus `svchost` ;
- services actifs / automatiques ;
- commandes de démarrage ;
- RAM libre ;
- charge CPU ;
- état Defender ;
- volumes C:/D:.

Aucun benchmark synthétique générant de gros volumes d'écritures SSD n'est lancé.

## Qualification

```powershell
.\install.ps1 -Mode Verify -OptimizationProfiles standard
```

Avec profils supplémentaires :

```powershell
.\install.ps1 -Mode Verify -OptimizationProfiles standard,privacy,gaming
```

Verdict attendu :

```text
VERDICT: V4 WINDOWS OPTIMIZATION READY
```

Le validateur refuse notamment les profils qui ciblent `SharedAccess`, `StorSvc`, Windows Update, Defender, Firewall, Hyper-V/HNS ou les chemins Registry de sécurité correspondants.

## Rollback

Rollback automatique de tous les profils V4 pour lesquels un état existe :

```powershell
.\install.ps1 -Mode Rollback
```

Rollback explicite d'un ensemble :

```powershell
.\install.ps1 -Mode Rollback -OptimizationProfiles standard,privacy,gaming
```

Les services ne sont pas arrêtés brutalement lors de Apply : seul leur type de démarrage est modifié. Un redémarrage est recommandé pour les profils qui le nécessitent.
