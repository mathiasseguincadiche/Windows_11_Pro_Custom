#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
RUNTIME_CONTRACT="$REPO_ROOT/config/wsl/runtime-contract.json"
required=(git curl jq docker kubectl helm terraform aws ansible gh trivy shellcheck shfmt minikube kind)
advisory_required=(terraform-docs actionlint yq tflint)
failed=0
warnings=0

ok() { printf '[OK] %s\n' "$*"; }
ko() { printf '[KO] %s\n' "$*"; failed=$((failed + 1)); }
warn() { printf '[AVERTISSEMENT] %s\n' "$*"; warnings=$((warnings + 1)); }

printf 'Validation stack DevOps WSL2\n\n'

printf 'Outils cœur\n'
for cmd in "${required[@]}"; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '[OK] %-16s %s\n' "$cmd" "$(command -v "$cmd")"
  else
    printf '[KO] %-16s absent\n' "$cmd"
    failed=$((failed + 1))
  fi
done

printf '\nOutils qualité additionnels (non bloquants pour Installation complete)\n'
for cmd in "${advisory_required[@]}"; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '[OK] %-16s %s\n' "$cmd" "$(command -v "$cmd")"
  else
    warn "$cmd absent; la stack cœur reste utilisable."
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
terraform-docs --version || true
actionlint -version || true
yq --version || true
tflint --version || true

printf '\nDocker daemon\n'
if docker info >/dev/null 2>&1; then
  ok 'Docker Engine accessible sans sudo.'
  logging_driver="$(docker info --format '{{.LoggingDriver}}' 2>/dev/null || true)"
  if [[ "$logging_driver" == local ]]; then
    ok 'Docker logging driver = local.'
  else
    ko "Docker logging driver inattendu: ${logging_driver:-inconnu}"
  fi
else
  ko 'Docker Engine non accessible sans sudo. Ferme WSL avec wsl.exe --shutdown puis relance Ubuntu.'
fi

if systemctl is-active --quiet docker 2>/dev/null; then
  ok 'Service systemd docker actif.'
else
  ko 'Service systemd docker inactif.'
fi

printf '\nFilesystem de travail\n'
if [[ ! -f "$RUNTIME_CONTRACT" ]]; then
  ko "Contrat WSL introuvable: $RUNTIME_CONTRACT"
elif ! command -v jq >/dev/null 2>&1; then
  ko 'Impossible de vérifier le contrat WSL: jq est absent.'
else
  forbidden_roots_raw=''
  managed_roots_raw=''

  if forbidden_roots_raw="$(
    jq -er '
      .forbiddenRoots
      | if type == "array"
           and length > 0
           and all(.[]; type == "string" and startswith("/") and length > 1)
        then .[]
        else error("forbiddenRoots invalide")
        end
    ' "$RUNTIME_CONTRACT"
  )"; then
    mapfile -t forbidden_roots <<< "$forbidden_roots_raw"
  else
    ko 'Contrat WSL invalide: forbiddenRoots est absent ou mal formé.'
    forbidden_roots=()
  fi

  if managed_roots_raw="$(
    jq -er '
      [(.workingRoots // []), (.utilityRoots // [])]
      | add
      | if type == "array"
           and length > 0
           and all(.[]; type == "string" and startswith("~/") and length > 2)
        then .[]
        else error("workingRoots/utilityRoots invalides")
        end
    ' "$RUNTIME_CONTRACT"
  )"; then
    mapfile -t managed_roots <<< "$managed_roots_raw"
  else
    ko 'Contrat WSL invalide: workingRoots/utilityRoots sont absents ou mal formés.'
    managed_roots=()
  fi

  home_forbidden=0
  for root in "${forbidden_roots[@]}"; do
    if [[ "$HOME" == "$root" || "$HOME" == "$root/"* ]]; then
      ko "HOME est sous une racine interdite par le contrat WSL: $HOME"
      home_forbidden=1
      break
    fi
  done
  if (( home_forbidden == 0 )); then
    ok "HOME Linux: $HOME"
  fi

  for declared_root in "${managed_roots[@]}"; do
    path="$HOME/${declared_root#~/}"
    if [[ ! -d "$path" ]]; then
      ko "Répertoire géré absent: $path"
      continue
    fi

    path_forbidden=0
    for root in "${forbidden_roots[@]}"; do
      if [[ "$path" == "$root" || "$path" == "$root/"* ]]; then
        ko "Racine Linux gérée sous un montage Windows interdit: $path"
        path_forbidden=1
        break
      fi
    done
    (( path_forbidden == 1 )) && continue

    fs_type="$(findmnt -T "$path" -n -o FSTYPE 2>/dev/null || true)"
    if [[ "$fs_type" == ext4* ]]; then
      ok "$path ($fs_type)"
    else
      ko "Racine Linux gérée hors ext4: $path (${fs_type:-inconnu})"
    fi
  done
fi

printf '\nProfil shell\n'
if bash "$SCRIPT_DIR/manage-shell-profile.sh" verify; then
  ok 'Profil shell DevOps opérationnel.'
else
  warn 'Profil shell DevOps incomplet; non bloquant pour la stack cœur.'
fi

printf '\nVS Code WSL\n'
if bash "$SCRIPT_DIR/manage-vscode-extensions.sh" verify; then
  ok 'Vérification VS Code WSL terminée.'
else
  warn 'Validation VS Code WSL non concluante; non bloquante pour la stack cœur.'
fi

printf '\nQualité GitHub Actions\n'
if ! compgen -G "$REPO_ROOT/.github/workflows/*.yml" >/dev/null; then
  warn 'Aucun workflow .yml trouvé pour actionlint.'
elif ! command -v actionlint >/dev/null 2>&1; then
  warn 'actionlint absent; validation locale des workflows ignorée.'
elif actionlint "$REPO_ROOT"/.github/workflows/*.yml; then
  ok 'actionlint valide les workflows du dépôt.'
else
  warn 'actionlint détecte une erreur dans les workflows; cela ne rend pas Docker/kubectl/Helm/Terraform inutilisables.'
fi

printf '\nTerraform smoke test\n'
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
cat > "$tmpdir/main.tf" <<'EOF'
terraform {
  required_version = ">= 1.0"
}

variable "environment" {
  type    = string
  default = "validation"
}

output "environment" {
  value = var.environment
}
EOF
if terraform -chdir="$tmpdir" fmt -check -diff >/dev/null && terraform -chdir="$tmpdir" validate >/dev/null; then
  ok 'Terraform fmt/validate opérationnels.'
else
  ko 'Terraform smoke test en échec.'
fi

if [[ $failed -gt 0 ]]; then
  printf '\nVERDICT: KO CŒUR DEVOPS (%d contrôle(s) critique(s) en échec, %d avertissement(s))\n' "$failed" "$warnings"
  exit 1
fi

printf '\nVERDICT: DEVOPS CORE READY (%d avertissement(s) non bloquant(s))\n' "$warnings"
