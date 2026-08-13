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
profile_script="$script_dir/manage-shell-profile.sh"
state_dir="$HOME/.config/windows11-pro-custom/state"
state_file="$state_dir/terminal-packages.before"
packages=(starship fzf zoxide eza ripgrep fd-find bat tree)

[[ -x "$profile_script" || -r "$profile_script" ]] || { echo "[ERREUR] Gestionnaire de profil absent: $profile_script" >&2; exit 1; }

package_installed() {
  # ${Status} doit rester littéral: c'est le format demandé à dpkg-query.
  # shellcheck disable=SC2016
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fq 'install ok installed'
}

command_ready() {
  case "$1" in
    fd-find) command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1 ;;
    bat) command -v bat >/dev/null 2>&1 || command -v batcat >/dev/null 2>&1 ;;
    ripgrep) command -v rg >/dev/null 2>&1 ;;
    *) command -v "$1" >/dev/null 2>&1 ;;
  esac
}

missing_packages() {
  local pkg
  for pkg in "${packages[@]}"; do
    if ! package_installed "$pkg" || ! command_ready "$pkg"; then
      printf '%s\n' "$pkg"
    fi
  done
}

audit() {
  local pkg
  local missing=0
  printf 'Terminal DevOps V10 - état réel Ubuntu\n\n'
  for pkg in "${packages[@]}"; do
    if package_installed "$pkg" && command_ready "$pkg"; then
      printf '[DÉJÀ OK] %-12s installé et commande disponible\n' "$pkg"
    else
      printf '[À FAIRE] %-12s absent ou commande indisponible\n' "$pkg"
      missing=$((missing + 1))
    fi
  done
  if bash "$profile_script" verify >/dev/null 2>&1; then
    echo '[DÉJÀ OK] Profil Bash/Starship conforme.'
  else
    echo '[À FAIRE] Profil Bash/Starship non conforme.'
    missing=$((missing + 1))
  fi
  printf '\nRésumé: %d élément(s) à traiter.\n' "$missing"
}

verify() {
  local missing
  missing="$(missing_packages)"
  if [[ -n "$missing" ]]; then
    printf '[KO] Paquets/commandes terminal non conformes:\n%s\n' "$missing" >&2
    return 1
  fi
  bash "$profile_script" verify
  STARSHIP_CONFIG="$HOME/.config/windows11-pro-custom/starship.toml" starship prompt >/dev/null
  echo '[OK] Terminal DevOps V10 validé factuellement.'
}

if [[ "$mode" == audit ]]; then
  audit
  exit 0
fi

if [[ "$mode" == verify ]]; then
  verify
  exit 0
fi

if [[ "$mode" == apply ]]; then
  mapfile -t missing < <(missing_packages)
  profile_ok=false
  if bash "$profile_script" verify >/dev/null 2>&1; then profile_ok=true; fi

  if ((${#missing[@]} == 0)) && [[ "$profile_ok" == true ]]; then
    echo '[DÉJÀ OK] Terminal DevOps V10 déjà conforme; aucun paquet ni profil modifié.'
    exit 0
  fi

  mkdir -p "$state_dir"
  if [[ ! -e "$state_file" ]]; then
    printf '%s\n' "${missing[@]}" > "$state_file"
    echo "[OK] État initial des paquets enregistré: $state_file"
  fi

  if ((${#missing[@]} > 0)); then
    printf '[EN COURS] Installation APT: %s\n' "${missing[*]}"
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends "${missing[@]}"
    echo '[FAIT] Paquets terminal installés.'
  else
    echo '[DÉJÀ OK] Tous les paquets terminal sont déjà présents.'
  fi

  bash "$profile_script" apply
  verify
  echo '[FAIT] Terminal DevOps V10 convergé.'
  exit 0
fi

if [[ ! -e "$state_file" ]]; then
  echo '[DÉJÀ OK] Aucun état initial Terminal V10 enregistré; rollback paquet inutile.'
  bash "$profile_script" rollback
  exit 0
fi

bash "$profile_script" rollback
mapfile -t installed_by_v10 < <(grep -Ev '^[[:space:]]*$' "$state_file" || true)
if ((${#installed_by_v10[@]} > 0)); then
  printf '[EN COURS] Retrait des paquets ajoutés par V10: %s\n' "${installed_by_v10[*]}"
  sudo apt-get remove -y "${installed_by_v10[@]}"
fi
rm -f "$state_file"
echo "[FAIT] Terminal DevOps V10 restauré à l'état initial enregistré."
