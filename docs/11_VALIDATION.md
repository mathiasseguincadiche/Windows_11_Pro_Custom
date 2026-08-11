# Validation V3

## Règle de qualification

La machine est considérée **V3 READY** uniquement lorsque les contrôles Windows et WSL2 sont tous les deux verts.

## Windows

Commande stricte :

```powershell
.\install.ps1 -Mode Verify
```

Le validateur `scripts/bootstrap/11_validate_v3.ps1` contrôle notamment :

- Windows 11 ;
- `C:` en NTFS ;
- `D:` en NTFS ;
- Defender Antivirus actif ;
- protection temps réel Defender active ;
- absence d'exclusion Defender racine `C:\` ou `D:\` ;
- commande WSL disponible ;
- profil `.wslconfig` identique au profil demandé ;
- distribution Ubuntu présente ;
- emplacement WSL sous `D:\WSL\Ubuntu-DevOps` ;
- présence du VHDX sur le SSD DATA ;
- configuration VS Code identique à la V3 ;
- configuration WezTerm identique à la V3.

Rapports locaux :

```text
reports/preflight.json
reports/windows/system-audit.json
reports/defender-baseline.json
reports/validation-v3.json
```

Verdict attendu :

```text
VERDICT: V3 WINDOWS READY
```

## WSL2 / DevOps

Après installation de la stack et un `wsl --shutdown` :

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

Le validateur Linux contrôle :

- Git ;
- Docker Engine et Compose ;
- kubectl ;
- Helm ;
- Minikube ;
- kind ;
- Terraform ;
- AWS CLI v2 ;
- Ansible Core ;
- GitHub CLI ;
- Trivy ;
- ShellCheck ;
- shfmt ;
- terraform-docs ;
- actionlint ;
- yq ;
- TFLint ;
- Docker accessible sans sudo ;
- service Docker systemd actif ;
- driver de logs Docker `local` ;
- HOME hors de `/mnt/c` et `/mnt/d` ;
- répertoires `projects`, `labs`, `repositories`, `workspace`, `backups` ;
- profil shell versionné ;
- workflows GitHub Actions avec actionlint ;
- smoke test Terraform.

Verdict attendu :

```text
VERDICT: V3 DEVOPS READY
```

## Qualification du dépôt GitHub

La PR V3 doit également être verte sur :

- parsing PowerShell ;
- PSScriptAnalyzer niveau Error ;
- `bash -n` ;
- ShellCheck ;
- JSON ;
- syntaxe Lua WezTerm ;
- actionlint ;
- garde-fou contre les opérations de formatage disque et la désactivation temps réel Defender.

## Règle de sortie

Un seul `KO` bloque la qualification. Une optimisation non auditée, non vérifiable ou sans rollback ne doit pas être fusionnée dans `main`.
