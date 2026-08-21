#!/usr/bin/env bash
set -Eeuo pipefail

mode="${1:-audit}"
if (($# > 0)); then shift; fi
case "$mode" in
  audit|apply|verify|rollback) ;;
  *) echo "Usage: $0 {audit|apply|verify|rollback} [--target-user USER]" >&2; exit 2 ;;
esac

target_user=""
while (($# > 0)); do
  case "$1" in
    --target-user)
      [[ $# -ge 2 ]] || { echo '[ERREUR] --target-user requiert une valeur.' >&2; exit 2; }
      target_user="$2"
      shift 2
      ;;
    *)
      echo "[ERREUR] Argument inconnu: $1" >&2
      exit 2
      ;;
  esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
profile_script="$script_dir/manage-shell-profile.sh"
packages=(starship fzf zoxide eza ripgrep fd-find bat tree)

[[ -x "$profile_script" || -r "$profile_script" ]] || { echo "[ERREUR] Gestionnaire de profil absent: $profile_script" >&2; exit 1; }

if [[ ${EUID} -eq 0 ]]; then
  [[ -n "$target_user" ]] || {
    echo '[ERREUR] Une exécution root de ce gestionnaire exige --target-user afin de préserver le HOME utilisateur.' >&2
    exit 1
  }
else
  current_user="$(id -un)"
  if [[ -n "$target_user" && "$target_user" != "$current_user" ]]; then
    echo "[ERREUR] Un utilisateur non-root ne peut gérer que son propre terminal: courant=$current_user cible=$target_user" >&2
    exit 1
  fi
  target_user="$current_user"
fi

if [[ "$target_user" == root || ! "$target_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "[ERREUR] Utilisateur cible invalide: $target_user" >&2
  exit 1
fi

passwd_entry="$(getent passwd "$target_user" || true)"
[[ -n "$passwd_entry" ]] || { echo "[ERREUR] Utilisateur cible absent: $target_user" >&2; exit 1; }
target_home="$(cut -d: -f6 <<<"$passwd_entry")"
target_group="$(id -gn "$target_user")"
[[ -n "$target_home" && "$target_home" == /* ]] || { echo "[ERREUR] HOME invalide pour $target_user: $target_home" >&2; exit 1; }

state_dir="$target_home/.config/windows11-pro-custom/state"
state_file="$state_dir/terminal-packages.before"

target_run() {
  if [[ ${EUID} -eq 0 ]]; then
    runuser --user "$target_user" -- env HOME="$target_home" USER="$target_user" LOGNAME="$target_user" "$@"
  else
    "$@"
  fi
}

profile_run() {
  target_run bash "$profile_script" "$@"
}

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

record_initial_packages() {
  local -a initial=("$@")
  if [[ -e "$state_file" ]]; then
    return 0
  fi

  target_run mkdir -p "$state_dir"
  if [[ ${EUID} -eq 0 ]]; then
    local tmp_state
    tmp_state="$(mktemp)"
    printf '%s\n' "${initial[@]}" > "$tmp_state"
    install -m 0644 -o "$target_user" -g "$target_group" "$tmp_state" "$state_file"
    rm -f "$tmp_state"
  else
    printf '%s\n' "${initial[@]}" > "$state_file"
  fi
  echo "[OK] État initial des paquets enregistré: $state_file"
}

audit() {
  local pkg
  local missing=0
  printf 'Terminal DevOps - état réel Ubuntu pour %s\n\n' "$target_user"
  for pkg in "${packages[@]}"; do
    if package_installed "$pkg" && command_ready "$pkg"; then
      printf '[DÉJÀ OK] %-12s installé et commande disponible\n' "$pkg"
    else
      printf '[À FAIRE] %-12s absent ou commande indisponible\n' "$pkg"
      missing=$((missing + 1))
    fi
  done
  if profile_run verify >/dev/null 2>&1; then
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
  profile_run verify
  target_run env STARSHIP_CONFIG="$target_home/.config/windows11-pro-custom/starship.toml" starship prompt >/dev/null
  echo "[OK] Terminal DevOps validé factuellement pour $target_user."
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
  if profile_run verify >/dev/null 2>&1; then profile_ok=true; fi

  if ((${#missing[@]} == 0)) && [[ "$profile_ok" == true ]]; then
    echo '[DÉJÀ OK] Terminal DevOps déjà conforme; aucun paquet ni profil modifié.'
    exit 0
  fi

  if ((${#missing[@]} > 0)) && [[ ${EUID} -ne 0 ]]; then
    printf '[ERREUR] Paquets système manquants: %s\n' "${missing[*]}" >&2
    echo '[ERREUR] Le mode Apply automatisé doit être lancé par l orchestrateur avec root WSL et --target-user; aucun prompt sudo interactif n est utilisé.' >&2
    exit 1
  fi

  record_initial_packages "${missing[@]}"

  if ((${#missing[@]} > 0)); then
    printf '[EN COURS] Installation APT non interactive via root WSL: %s\n' "${missing[*]}"
    apt-get update
    apt-get install -y --no-install-recommends "${missing[@]}"
    echo '[FAIT] Paquets terminal installés via la frontière root WSL.'
  else
    echo '[DÉJÀ OK] Tous les paquets terminal sont déjà présents.'
  fi

  profile_run apply
  verify
  echo "[FAIT] Terminal DevOps convergé pour $target_user."
  exit 0
fi

mapfile -t installed_by_terminal < <(grep -Ev '^[[:space:]]*$' "$state_file" 2>/dev/null || true)
if ((${#installed_by_terminal[@]} > 0)) && [[ ${EUID} -ne 0 ]]; then
  printf '[ERREUR] Le rollback doit retirer des paquets système: %s\n' "${installed_by_terminal[*]}" >&2
  echo '[ERREUR] Relance le rollback via l orchestrateur root WSL avec --target-user; aucun sudo interactif n est utilisé.' >&2
  exit 1
fi

if [[ ! -e "$state_file" ]]; then
  echo '[DÉJÀ OK] Aucun état initial Terminal DevOps enregistré; rollback paquet inutile.'
  profile_run rollback
  exit 0
fi

profile_run rollback
if ((${#installed_by_terminal[@]} > 0)); then
  printf '[EN COURS] Retrait des paquets ajoutés par le gestionnaire terminal: %s\n' "${installed_by_terminal[*]}"
  apt-get remove -y "${installed_by_terminal[@]}"
fi
rm -f "$state_file"
echo "[FAIT] Terminal DevOps restauré à l'état initial enregistré pour $target_user."
