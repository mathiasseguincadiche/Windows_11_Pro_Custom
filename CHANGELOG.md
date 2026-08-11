# Changelog

## Unreleased — OpenClaw + OpenRouter

- ajout d'un bootstrap optionnel OpenClaw + OpenRouter natif Windows ;
- séparation stricte entre `D:\WSL` pour les workloads Linux DevOps et `D:\AI\OpenClaw` pour la pile IA ;
- clone/mise à jour protégée du plan de contrôle privé `openclaw_openrouter` sous `D:\AI\OpenClaw\control-plane` ;
- installation et qualification depuis `install.ps1` avec `-InstallOpenClawAI` et `-ValidateOpenClawAI` ;
- aucun effacement automatique de l'état OpenClaw pendant un rollback ;
- documentation dédiée `docs/19_OPENCLAW_OPENROUTER_WINDOWS.md`.

## V2

- tuning Windows réversible avec Audit / Apply / Verify / Rollback ;
- audit matériel, stockage, TRIM, mémoire, WSL et Defender ;
- Defender deny-by-default avec Performance Analyzer et rollback fiable ;
- WSL2 systemd + Docker Engine natif sans Docker Desktop ;
- kubectl, Helm, Minikube, kind, Terraform, AWS CLI v2, Ansible, GitHub CLI, Trivy, ShellCheck et shfmt ;
- rotation des logs Docker pour limiter la croissance du VHDX ;
- validation Bash, ShellCheck, PowerShell et JSON en CI ;
- runbook complet de réinstallation.

## V1

- architecture Windows 11 Pro + deux SSD NTFS ;
- WSL2 stocké sur `D:` sans partition EXT4 physique ;
- profils WSL2 standard / lab-heavy / NAT fallback ;
- bootstrap applications WinGet ;
- audit initial Defender ;
- documentation architecture, stockage, BIOS, applications, gaming et sauvegarde.