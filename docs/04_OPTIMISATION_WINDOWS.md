# Optimisation Windows

## Objectif

La machine dispose de 48 Go de RAM et de deux SSD PCIe 5.0. L'objectif est de réduire le bruit Windows sans casser Windows Update, Microsoft Store, Defender, WSL2, Hyper-V, Intel Arc ou le gaming.

La stratégie est désormais en deux couches :

1. `scripts/windows/10_tune.ps1` — base V2/V3 ;
2. `scripts/windows/40_v4_optimize.ps1` — profils V4 inspirés de WinUtil.

## Base V2/V3

Le moteur historique gère notamment :

- extensions de fichiers visibles ;
- fichiers cachés visibles ;
- notifications publicitaires Explorer désactivées ;
- Widgets masqués ;
- Advertising ID désactivé ;
- expériences personnalisées désactivées ;
- installations silencieuses d'applications suggérées désactivées ;
- conseils et suggestions Windows réduits ;
- Windows Consumer Features désactivées ;
- télémétrie maintenue à un niveau requis plutôt que cassée.

Son état initial est sauvegardé dans :

```text
state/windows-tweaks-backup.json
```

## V4 — profils WinUtil sur mesure

Moteur :

```powershell
.\scripts\windows\40_v4_optimize.ps1 -Mode Audit -Profile standard
.\scripts\windows\40_v4_optimize.ps1 -Mode Apply -Profile standard
.\scripts\windows\40_v4_optimize.ps1 -Mode Verify -Profile standard
.\scripts\windows\40_v4_optimize.ps1 -Mode Rollback -Profile standard
```

Profils disponibles :

- `standard` — quotidien, appliqué par défaut ;
- `privacy` — localisation et métadonnées périphériques ;
- `gaming` — Game Mode conservé, captures arrière-plan coupées ;
- `optional` — tuning services limité à DiagTrack / MapsBroker.

Détails complets : `docs/14_WINDOWS_OPTIMIZATION_V4.md`.

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
- Secure Boot / TPM.

Il ne supprime pas automatiquement Edge, OneDrive, Copilot ou des packages Windows en masse.

## WinUtil

WinUtil est utilisé comme **référence upstream**, pas comme exécuteur de la configuration du poste.

Le mapping versionné se trouve dans :

```text
config/winutil/mathias-winutil.json
```

Ce fichier documente les tweaks intégrés, optionnels, différés ou refusés. Il n'est pas présenté comme un export WinUtil directement importable.

## Restore point et rollback

Avant une application V4 via `install.ps1`, le dépôt tente de créer un point de restauration Windows puis sauvegarde l'état Registry/services de chaque profil sous :

```text
state/windows-v4/<profile>.before.json
```

Les sauvegardes initiales ne sont jamais écrasées.

## Mesure avant / après

```text
reports/windows/v4-benchmark-before.json
reports/windows/v4-benchmark-after.json
reports/windows/v4-benchmark-comparison.json
```

Le benchmark reste léger : aucun test synthétique générant de gros volumes d'écritures sur les SSD n'est exécuté.
