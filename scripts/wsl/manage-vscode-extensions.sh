#!/usr/bin/env bash
set -Eeuo pipefail

mode="${1:-audit}"
case "$mode" in
  audit|apply|verify|rollback) ;;
  *) echo "Usage: $0 {audit|apply|verify|rollback}" >&2; exit 2 ;;
esac

if [[ ${EUID} -eq 0 ]]; then
  echo "[ERREUR] Lance ce script avec ton utilisateur WSL, pas root." >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
extensions_file="$repo_root/config/vscode/extensions-wsl.txt"
state_dir="$HOME/.config/windows11-pro-custom/state"
state_file="$state_dir/vscode-wsl-extensions.before"

[[ -r "$extensions_file" ]] || { echo "[ERREUR] Liste extensions WSL absente: $extensions_file" >&2; exit 1; }
if ! command -v code >/dev/null 2>&1; then
  echo '[ERREUR] La commande code est absente dans WSL. Vérifie VS Code Windows + extension WSL.' >&2
  exit 1
fi

mapfile -t requested < <(grep -Ev '^\s*(#|$)' "$extensions_file")

list_installed() {
  code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort -u
}

if [[ "$mode" == audit ]]; then
  echo 'Extensions WSL demandées:'
  printf '  %s\n' "${requested[@]}"
  echo 'Extensions visibles dans l’hôte WSL:'
  list_installed | sed 's/^/  /'
  exit 0
fi

if [[ "$mode" == apply ]]; then
  mkdir -p "$state_dir"
  if [[ ! -e "$state_file" ]]; then
    list_installed > "$state_file"
  fi
  for extension in "${requested[@]}"; do
    code --install-extension "$extension" --force
  done
  echo '[OK] Extensions VS Code installées dans l’hôte WSL.'
  exit 0
fi

if [[ "$mode" == verify ]]; then
  mapfile -t installed < <(list_installed)
  failed=0
  for extension in "${requested[@]}"; do
    extension_lower="${extension,,}"
    if printf '%s\n' "${installed[@]}" | grep -Fxq "$extension_lower"; then
      echo "[OK] $extension"
    else
      echo "[KO] Extension WSL absente: $extension" >&2
      failed=$((failed + 1))
    fi
  done
  (( failed == 0 )) || exit 1
  echo '[OK] Extensions VS Code WSL validées.'
  exit 0
fi

[[ -r "$state_file" ]] || { echo "[ERREUR] État extensions WSL absent: $state_file" >&2; exit 1; }
mapfile -t before < "$state_file"
for extension in "${requested[@]}"; do
  extension_lower="${extension,,}"
  if ! printf '%s\n' "${before[@]}" | grep -Fxq "$extension_lower"; then
    code --uninstall-extension "$extension" || true
  fi
done
echo '[OK] Extensions VS Code WSL restaurées.'
