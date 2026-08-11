# Stack DevOps WSL2

## Windows natif

- Visual Studio Code avec Remote WSL.
- WezTerm.
- navigateurs et outils bureautiques.

## Ubuntu WSL2

Le socle Linux est préparé par :

```bash
./scripts/wsl/bootstrap.sh
```

Répertoires créés :

```text
~/projects
~/labs
~/repositories
~/scripts
~/workspace
~/backups
```

## Cible DevOps

La couche suivante du dépôt doit automatiser avec les dépôts éditeurs officiels :

- Docker Engine + Compose plugin ;
- kubectl ;
- Helm ;
- Minikube et/ou kind ;
- Terraform ;
- AWS CLI ;
- Ansible ;
- GitHub CLI ;
- tflint, terraform-docs, actionlint, shfmt et Trivy.

Docker Desktop n'est pas requis par l'architecture cible.
