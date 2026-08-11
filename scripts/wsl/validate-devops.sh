#!/usr/bin/env bash
set -Eeuo pipefail

required=(git curl jq docker kubectl helm terraform aws ansible gh trivy shellcheck shfmt minikube kind)
failed=0

printf 'Validation stack DevOps WSL2\n\n'

for cmd in "${required[@]}"; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '[OK] %-12s %s\n' "$cmd" "$(command -v "$cmd")"
  else
    printf '[KO] %-12s absent\n' "$cmd"
    failed=$((failed + 1))
  fi
done

printf '\nVersions principales\n'
git --version || true
docker --version || true
docker compose version || true
kubectl version --client || true
helm version --short || true
terraform version || true
aws --version || true
ansible --version | head -n 2 || true
gh --version | head -n 1 || true
trivy --version || true
minikube version || true
kind version || true

printf '\nDocker daemon\n'
if docker info >/dev/null 2>&1; then
  echo '[OK] Docker Engine accessible sans sudo.'
else
  echo '[AVERTISSEMENT] Docker Engine non accessible. Ferme WSL avec wsl.exe --shutdown puis relance la distribution.'
fi

printf '\nFilesystem de travail\n'
case "$HOME" in
  /mnt/c/*|/mnt/d/*)
    echo "[KO] HOME est sur un filesystem Windows: $HOME"
    failed=$((failed + 1))
    ;;
  *)
    echo "[OK] HOME Linux: $HOME"
    ;;
esac

for dir in projects labs repositories workspace; do
  if [[ -d "$HOME/$dir" ]]; then
    echo "[OK] $HOME/$dir"
  else
    echo "[KO] Répertoire absent: $HOME/$dir"
    failed=$((failed + 1))
  fi
done

if [[ $failed -gt 0 ]]; then
  printf '\nVERDICT: KO (%d contrôle(s) en échec)\n' "$failed"
  exit 1
fi

printf '\nVERDICT: STACK DEVOPS READY\n'
