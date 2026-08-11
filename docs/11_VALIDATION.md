# Validation

La V1 vérifie au minimum :

- Windows 11 ;
- `C:` en NTFS ;
- `D:` en NTFS ;
- présence de `.wslconfig` après application ;
- commande WSL disponible ;
- protection temps réel Defender active.

Commande :

```powershell
.\scripts\bootstrap\07_validate.ps1
```

Rapports :

```text
reports/preflight.json
reports/defender-baseline.json
reports/validation.json
```

Un `KO` doit être corrigé avant d'ajouter les optimisations avancées.
