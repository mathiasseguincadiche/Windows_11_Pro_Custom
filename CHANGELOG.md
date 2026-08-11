# Changelog

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
