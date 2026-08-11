# Validation

## V2 — contrôles obligatoires

Le poste est considéré prêt uniquement lorsque les contrôles Windows et WSL2 attendus sont verts.

### Windows

```powershell
.\install.ps1 -Mode Audit
.\install.ps1 -Mode Verify
```

La validation couvre notamment :

- Windows 11 ;
- `C:` en NTFS ;
- `D:` en NTFS ;
- aucune dépendance à une partition EXT4 physique ;
- présence de `.wslconfig` après application ;
- commande WSL disponible ;
- protection temps réel Defender active ;
- état CPU / RAM / GPU ;
- état des SSD et volumes ;
- TRIM ;
- plan d'alimentation ;
- compression mémoire Windows ;
- configuration WSL.

Rapports locaux :

```text
reports/preflight.json
reports/windows/system-audit.json
reports/defender-baseline.json
reports/validation.json
```

### WSL2 / DevOps

Après le bootstrap DevOps et un `wsl --shutdown` :

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

Le validateur Linux contrôle :

- Git ;
- curl ;
- jq ;
- Docker Engine ;
- Docker Compose ;
- kubectl ;
- Helm ;
- Terraform ;
- AWS CLI ;
- Ansible ;
- GitHub CLI ;
- Trivy ;
- ShellCheck ;
- shfmt ;
- Minikube ;
- kind ;
- HOME Linux hors de `/mnt/c` et `/mnt/d` ;
- présence des répertoires de travail.

Verdict attendu :

```text
VERDICT: STACK DEVOPS READY
```

## Règle de sortie

Un contrôle `KO` doit être corrigé avant de considérer la machine comme qualifiée. Une optimisation qui ne peut pas être auditée, vérifiée ou annulée ne doit pas être intégrée au bootstrap principal.
