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
source_profile="$repo_root/config/wsl/bashrc.d/devops.sh"
config_dir="$HOME/.config/windows11-pro-custom"
state_dir="$config_dir/state"
target_profile="$config_dir/devops.sh"
backup_bashrc="$state_dir/bashrc.before"
marker_begin="# BEGIN windows11-pro-custom"
marker_end="# END windows11-pro-custom"
source_line="source \"$target_profile\""

[[ -r "$source_profile" ]] || { echo "[ERREUR] Profil source absent: $source_profile" >&2; exit 1; }

audit() {
  printf 'Profil cible: %s\n' "$target_profile"
  printf 'Profil installé: %s\n' "$(test -r "$target_profile" && echo oui || echo non)"
  printf 'Hook .bashrc: %s\n' "$(grep -Fq "$marker_begin" "$HOME/.bashrc" 2>/dev/null && echo oui || echo non)"
}

if [[ "$mode" == audit ]]; then
  audit
  exit 0
fi

if [[ "$mode" == apply ]]; then
  mkdir -p "$state_dir"
  if [[ ! -e "$backup_bashrc" ]]; then
    if [[ -e "$HOME/.bashrc" ]]; then
      cp "$HOME/.bashrc" "$backup_bashrc"
    else
      : > "$backup_bashrc"
    fi
  fi

  install -m 0644 "$source_profile" "$target_profile"
  if ! grep -Fq "$marker_begin" "$HOME/.bashrc" 2>/dev/null; then
    {
      printf '\n%s\n' "$marker_begin"
      printf '%s\n' "$source_line"
      printf '%s\n' "$marker_end"
    } >> "$HOME/.bashrc"
  fi
  echo '[OK] Profil shell DevOps installé.'
  exit 0
fi

if [[ "$mode" == verify ]]; then
  cmp -s "$source_profile" "$target_profile" || { echo '[KO] Profil DevOps différent de la source.' >&2; exit 1; }
  grep -Fq "$marker_begin" "$HOME/.bashrc" || { echo '[KO] Hook .bashrc absent.' >&2; exit 1; }
  grep -Fq "$source_line" "$HOME/.bashrc" || { echo '[KO] Source du profil absente de .bashrc.' >&2; exit 1; }
  echo '[OK] Profil shell DevOps validé.'
  exit 0
fi

[[ -e "$backup_bashrc" ]] || { echo "[ERREUR] Sauvegarde .bashrc absente: $backup_bashrc" >&2; exit 1; }
cp "$backup_bashrc" "$HOME/.bashrc"
rm -f "$target_profile"
echo '[OK] Profil shell DevOps restauré.'
