# Microsoft Defender et performances

## Politique

Defender reste actif. Le dépôt ne désactive pas la protection temps réel et n'exclut jamais `C:\`, `D:\`, `wsl.exe`, PowerShell ou des extensions génériques.

Une exclusion éventuelle doit être :

1. justifiée par une mesure ;
2. limitée à un chemin précis ;
3. documentée ;
4. vérifiable ;
5. réversible.

## Audit initial

```powershell
.\scripts\defender\00_audit.ps1
```

## Mesure de l'impact des scans

PowerShell administrateur :

```powershell
.\scripts\defender\01_record.ps1 -Seconds 60
```

Pendant la capture, reproduire le workload réel : clone Git, extraction d'archive, build, `docker build`, génération de dépendances, etc.

Puis :

```powershell
.\scripts\defender\02_report.ps1
```

Les résultats servent à décider si une optimisation est réellement nécessaire.

## Sources techniques

- Microsoft Defender Antivirus Performance Analyzer
- `New-MpPerformanceRecording`
- `Get-MpPerformanceReport`
