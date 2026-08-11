# Architecture cible

## Séparation des rôles

```text
SSD 1 - Crucial T705
└── C: NTFS
    ├── Windows 11 Pro
    ├── applications Windows
    └── profils utilisateur

SSD 2 - Crucial T705
└── D: NTFS
    ├── DATA
    ├── WSL
    │   └── Ubuntu-DevOps
    │       └── ext4.vhdx
    ├── ISO
    ├── BACKUPS
    └── EXPORTS
```

`ext4.vhdx` est un **fichier** stocké sur le volume NTFS `D:`. Le deuxième SSD n'est jamais formaté en EXT4.

## Frontière Windows / Linux

Windows natif héberge l'interface graphique, les applications bureautiques, les navigateurs, Steam, WezTerm et VS Code.

WSL2 héberge les outils Linux DevOps : Docker Engine, Compose, kubectl, Helm, Terraform, AWS CLI, Ansible et les outils de qualité shell/IaC.

## Règle de stockage des dépôts

Pour les commandes exécutées sous Linux :

```text
/home/<user>/projects
```

Éviter les dépôts actifs dans `/mnt/c` ou `/mnt/d` afin de ne pas imposer les accès inter-filesystems à tous les petits fichiers de build.

## Objectifs

1. Reproductibilité.
2. Performance I/O.
3. Sécurité conservée.
4. Rollback possible.
5. Pas de tweak non documenté.
