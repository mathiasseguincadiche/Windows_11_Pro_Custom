# Stockage

## Règle absolue

Les deux SSD physiques restent en **NTFS**.

| Disque | Lettre | FS | Rôle |
|---|---|---|---|
| Crucial T705 #1 | C: | NTFS | Windows 11 Pro et applications |
| Crucial T705 #2 | D: | NTFS | DATA, WSL2 VHDX, ISO, sauvegardes, exports |

Aucune commande de ce dépôt ne doit formater un disque automatiquement.

## Arborescence DATA

```text
D:\
├── DATA\
├── WSL\
│   └── Ubuntu-DevOps\
├── ISO\
├── BACKUPS\
└── EXPORTS\
```

## WSL2

La distribution est installée à l'emplacement :

```text
D:\WSL\Ubuntu-DevOps
```

Le VHDX est géré par WSL. Les projets Linux restent dans `/home/<user>/projects` à l'intérieur de la distribution.
