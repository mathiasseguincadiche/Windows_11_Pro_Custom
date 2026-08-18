# Microsoft Defender et performances

## Politique

Defender reste actif. Le dépôt ne désactive pas la protection temps réel et n'exclut jamais automatiquement `C:\`, `E:\`, `wsl.exe`, PowerShell, des extensions génériques ou des processus.

Une exclusion éventuelle doit être :

1. justifiée par une mesure ;
2. limitée à un chemin précis ;
3. documentée ;
4. vérifiable ;
5. réversible.

## 1. Audit initial

```powershell
.\scripts\defender\00_audit.ps1
```

## 2. Mesure de l'impact des scans

PowerShell administrateur :

```powershell
.\scripts\defender\01_record.ps1 -Seconds 60
```

Pendant la capture, reproduire le workload réel : clone Git, extraction d'archive, build, génération de dépendances, copie de nombreux petits fichiers, etc.

Puis :

```powershell
.\scripts\defender\02_report.ps1
```

Le rapport brut est conservé dans `reports/defender/performance-report.json`.

## 3. Approbation explicite

Le fichier :

```text
config/defender/exclusions.approved.json
```

est vide par défaut.

Une exclusion n'y est ajoutée qu'après analyse d'un hotspot démontré. Le moteur refuse :

- une racine de disque telle que `C:\` ou `E:\` ;
- les wildcards ;
- les racines de partage réseau ;
- les fichiers exécutables et scripts ;
- les exclusions de processus ;
- les exclusions globales d'extensions.

## 4. Application / audit / rollback

```powershell
.\scripts\defender\03_apply_approved_exclusions.ps1 -Mode Audit
.\scripts\defender\03_apply_approved_exclusions.ps1 -Mode Apply
.\scripts\defender\03_apply_approved_exclusions.ps1 -Mode Rollback
```

L'état des exclusions existantes est sauvegardé localement dans `state/` avant modification.

## WSL2

Le dépôt n'exclut pas automatiquement `E:\WSL`, le VHDX Ubuntu ou `wsl.exe`. Une optimisation de ce type serait beaucoup trop large sans preuve issue de Defender Performance Analyzer.

## Objectif réel

Le but n'est pas d'obtenir « zéro scan », mais d'éviter qu'un chemin de cache ou de build précisément identifié ne monopolise le CPU et les I/O pendant un workload DevOps. La protection du système Windows reste active.

## Sources techniques

- Microsoft Defender Antivirus Performance Analyzer ;
- `New-MpPerformanceRecording` ;
- `Get-MpPerformanceReport`.
