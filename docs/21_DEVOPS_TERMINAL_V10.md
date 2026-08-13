# V10 — WezTerm + Bash DevOps + VS Code

## Objectif

WezTerm est le terminal Windows principal. Il ouvre Ubuntu WSL2 et Bash. VS Code utilise le même Bash, le même `.bashrc`, les mêmes alias, complétions et le même prompt Starship.

```text
Windows 11
├── WezTerm (principal)
│   ├── Ubuntu DevOps / Bash (défaut)
│   └── PowerShell 7 (secondaire)
└── VS Code
    └── Ubuntu WSL / Bash (terminal par défaut)
        └── ~/.config/windows11-pro-custom/devops.sh
            ├── Starship
            ├── fzf
            ├── zoxide
            ├── eza / bat / fd / ripgrep
            ├── Git / Docker
            ├── kubectl / Helm
            ├── Terraform / Ansible / AWS / gh
            └── ~/.config/windows11-pro-custom/local.sh (optionnel, non géré)
```

## Principes

- aucune commande réseau au démarrage de Bash ;
- aucune donnée personnelle supposée ;
- PowerShell 7 reste disponible dans WezTerm et VS Code ;
- le profil Bash est géré avec `audit/apply/verify/rollback` ;
- un second `apply` conforme est un no-op ;
- le `.bashrc` n’obtient qu’un seul bloc géré par le dépôt ;
- JetBrainsMono Nerd Font est installé par WinGet côté Windows ;
- Starship et les outils CLI sont fournis par les dépôts Ubuntu 26.04 côté WSL.

## Outils de confort

- `starship` : prompt contextuel Git/Kubernetes/AWS/Terraform/Python/Docker ;
- `fzf` : historique `Ctrl+R`, fichiers `Ctrl+T`, navigation `Alt+C` ;
- `zoxide` : navigation intelligente avec `z <nom>` ;
- `eza` : `ll`, `la`, `l`, `lt` ;
- `bat` : coloration des fichiers sans remplacer `cat` ;
- `fd`/`fdfind` : recherche de fichiers ;
- `rg` : recherche de texte ;
- `tree` : arborescences.

## Alias principaux

- Git : `gst`, `gco`, `gcb`, `gpl`, `gps`, `glog`, `gd`, `gds` ;
- Docker : `d`, `dc`, `dps`, `di`, `dlog`, `dex`, `dcu`, `dcd`, `dcl` ;
- Kubernetes : `k`, `kgp`, `kgs`, `kgd`, `kgn`, `kga`, `klogs`, `kexec`, `kctx`, `kns` ;
- Helm : `h`, `hls`, `hst`, `hup` ;
- Terraform : `tf`, `tfi`, `tfp`, `tfa`, `tfd`, `tfo`, `tfv`, `tff` ;
- Ansible/AWS : `a`, `ap`, `av`, `awswho`, `awsp`.

## Gestion du profil

Depuis Ubuntu WSL :

```bash
bash scripts/wsl/manage-shell-profile.sh audit
bash scripts/wsl/manage-shell-profile.sh apply
bash scripts/wsl/manage-shell-profile.sh verify
bash scripts/wsl/manage-shell-profile.sh rollback
```

Le parcours recommandé reste `install.ps1` côté Windows, qui décide depuis l’état réel de la machine et ne lance Apply que si Verify constate un écart.

## Personnalisation locale

Les réglages personnels ou variables privées doivent aller dans :

```text
~/.config/windows11-pro-custom/local.sh
```

Ce fichier n’est ni créé ni versionné par le dépôt et peut contenir des variables propres à la machine. Ne jamais y placer un secret destiné à être commité.
