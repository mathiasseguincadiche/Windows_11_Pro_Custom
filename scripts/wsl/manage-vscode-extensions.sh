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
  echo '[AVERTISSEMENT] La commande code est absente dans WSL. VS Code Windows/Remote WSL pourra être initialisé plus tard; ce point ne bloque pas la stack DevOps.' >&2
  exit 0
fi

mapfile -t requested < <(grep -Ev '^\s*(#|$)' "$extensions_file")

list_installed() {
  code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort -u
}

if [[ "$mode" == audit ]]; then
  echo 'Extensions WSL demandées:'
  printf '  %s\n' "${requested[@]}"
  echo "Extensions visibles dans l'hôte WSL:"
  list_installed | sed 's/^/  /'
  exit 0
fi

if [[ "$mode" == apply ]]; then
  mkdir -p "$state_dir"
  if [[ ! -e "$state_file" ]]; then
    list_installed > "$state_file"
  fi

  warnings=0
  for extension in "${requested[@]}"; do
    if code --install-extension "$extension" --force; then
      echo "[OK] Extension WSL prête: $extension"
    else
      echo "[AVERTISSEMENT] Installation extension WSL non concluante: $extension. La workstation continue; relance cette étape plus tard." >&2
      warnings=$((warnings + 1))
    fi
  done
  echo "[OK] Gestion extensions VS Code WSL terminée avec $warnings avertissement(s)."
  exit 0
fi

if [[ "$mode" == verify ]]; then
  mapfile -t installed < <(list_installed)
  warnings=0
  for extension in "${requested[@]}"; do
    extension_lower="${extension,,}"
    if printf '%s\n' "${installed[@]}" | grep -Fxq "$extension_lower"; then
      echo "[OK] $extension"
    else
      echo "[AVERTISSEMENT] Extension WSL absente: $extension | non bloquant pour Installation complete." >&2
      warnings=$((warnings + 1))
    fi
  done
  echo "[OK] Vérification VS Code WSL terminée avec $warnings avertissement(s)."
  exit 0
fi

if [[ ! -r "$state_file" ]]; then
  echo "[AVERTISSEMENT] État extensions WSL absent: $state_file. Aucun rollback d extension n est nécessaire/provable." >&2
  exit 0
fi
mapfile -t before < "$state_file"
for extension in "${requested[@]}"; do
  extension_lower="${extension,,}"
  if ! printf '%s\n' "${before[@]}" | grep -Fxq "$extension_lower"; then
    code --uninstall-extension "$extension" || true
  fi
done
echo '[OK] Extensions VS Code WSL restaurées au mieux depuis l état enregistré.'
