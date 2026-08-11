# Sauvegarde et restauration

## Ce qui doit être sauvegardé

- dépôt de configuration Windows ;
- clés/configurations applicatives réellement utiles ;
- exports WSL réguliers ;
- données utilisateur ;
- clés SSH et secrets via un stockage chiffré approprié.

## WSL

Avant une modification importante :

```powershell
wsl --shutdown
wsl --export Ubuntu D:\BACKUPS\WSL\Ubuntu-DevOps.tar
```

Ne jamais copier à chaud un VHDX WSL actif comme stratégie principale de sauvegarde.
