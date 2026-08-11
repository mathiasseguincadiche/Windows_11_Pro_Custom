#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo 'Executer ce script avec votre utilisateur WSL, pas root.' >&2
  exit 1
fi

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl wget gnupg jq unzip zip rsync \
  git openssh-client build-essential python3 python3-pip pipx shellcheck

mkdir -p "$HOME/projects" "$HOME/labs" "$HOME/repositories" "$HOME/scripts" "$HOME/workspace" "$HOME/backups"

python3 -m pipx ensurepath || true

echo '[OK] Socle Linux WSL installe.'
