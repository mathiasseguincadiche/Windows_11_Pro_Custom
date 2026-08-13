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
source_starship="$repo_root/config/wsl/starship.toml"
config_dir="$HOME/.config/windows11-pro-custom"
state_dir="$config_dir/state"
target_profile="$config_dir/devops.sh"
target_starship="$config_dir/starship.toml"
backup_bashrc="$state_dir/bashrc.before"
marker_begin="# BEGIN windows11-pro-custom"
marker_end="# END windows11-pro-custom"
source_line="source \"$target_profile\""

[[ -r "$source_profile" ]] || { echo "[ERREUR] Profil source absent: $source_profile" >&2; exit 1; }
[[ -r "$source_starship" ]] || { echo "[ERREUR] Configuration Starship absente: $source_starship" >&2; exit 1; }

target_matches() {
  [[ -r "$target_profile" && -r "$target_starship" ]] || return 1
  cmp -s "$source_profile" "$target_profile" && cmp -s "$source_starship" "$target_starship"
}

hook_matches() {
  [[ -r "$HOME/.bashrc" ]] || return 1
  [[ "$(grep -Fc "$marker_begin" "$HOME/.bashrc" || true)" == "1" ]] || return 1
  [[ "$(grep -Fc "$marker_end" "$HOME/.bashrc" || true)" == "1" ]] || return 1
  grep -Fq "$source_line" "$HOME/.bashrc"
}

audit() {
  printf 'Profil cible: %s\n' "$target_profile"
  printf 'Starship cible: %s\n' "$target_starship"
  printf 'Profil installé: %s\n' "$(test -r "$target_profile" && echo oui || echo non)"
  printf 'Starship installé: %s\n' "$(test -r "$target_starship" && echo oui || echo non)"
  printf 'Contenu conforme: %s\n' "$(target_matches && echo oui || echo non)"
  printf 'Hook .bashrc conforme: %s\n' "$(hook_matches && echo oui || echo non)"
}

if [[ "$mode" == audit ]]; then
  audit
  if target_matches && hook_matches; then
    echo '[DÉJÀ OK] Profil Bash DevOps V10 conforme.'
  else
    echo '[À FAIRE] Profil Bash DevOps V10 incomplet ou différent.'
  fi
  exit 0
fi

if [[ "$mode" == verify ]]; then
  target_matches || { echo '[KO] Profil DevOps et/ou Starship différent de la source.' >&2; exit 1; }
  hook_matches || { echo '[KO] Hook .bashrc absent, dupliqué ou incorrect.' >&2; exit 1; }
  echo '[OK] Profil Bash DevOps V10 validé.'
  exit 0
fi

if [[ "$mode" == apply ]]; then
  if target_matches && hook_matches; then
    echo '[DÉJÀ OK] Profil Bash DevOps V10 déjà conforme; aucune réécriture.'
    exit 0
  fi

  mkdir -p "$state_dir"
  if [[ ! -e "$backup_bashrc" ]]; then
    if [[ -e "$HOME/.bashrc" ]]; then
      cp "$HOME/.bashrc" "$backup_bashrc"
    else
      : > "$backup_bashrc"
      : > "$HOME/.bashrc"
    fi
    echo "[OK] État initial .bashrc sauvegardé: $backup_bashrc"
  fi

  changes=0
  if [[ ! -r "$target_profile" ]] || ! cmp -s "$source_profile" "$target_profile"; then
    install -m 0644 "$source_profile" "$target_profile"
    echo '[FAIT] Profil Bash DevOps mis en conformité.'
    changes=$((changes + 1))
  else
    echo '[DÉJÀ OK] Profil Bash DevOps déjà conforme.'
  fi

  if [[ ! -r "$target_starship" ]] || ! cmp -s "$source_starship" "$target_starship"; then
    install -m 0644 "$source_starship" "$target_starship"
    echo '[FAIT] Configuration Starship mise en conformité.'
    changes=$((changes + 1))
  else
    echo '[DÉJÀ OK] Configuration Starship déjà conforme.'
  fi

  if ! hook_matches; then
    tmp_bashrc="$(mktemp)"
    awk -v begin="$marker_begin" -v end="$marker_end" '
      $0 == begin { skip=1; next }
      $0 == end { skip=0; next }
      !skip { print }
    ' "$HOME/.bashrc" > "$tmp_bashrc"
    {
      cat "$tmp_bashrc"
      printf '\n%s\n' "$marker_begin"
      printf '%s\n' "$source_line"
      printf '%s\n' "$marker_end"
    } > "$HOME/.bashrc"
    rm -f "$tmp_bashrc"
    echo '[FAIT] Hook .bashrc normalisé à une occurrence.'
    changes=$((changes + 1))
  else
    echo '[DÉJÀ OK] Hook .bashrc déjà conforme.'
  fi

  bash "$0" verify
  printf '[FAIT] Profil terminal V10 convergé (%d changement(s)).\n' "$changes"
  exit 0
fi

if [[ ! -e "$backup_bashrc" ]]; then
  echo '[DÉJÀ OK] Aucun état initial de profil enregistré; rollback inutile.'
  exit 0
fi

cp "$backup_bashrc" "$HOME/.bashrc"
rm -f "$target_profile" "$target_starship"
echo "[FAIT] Profil Bash/Starship restauré à l'état initial enregistré."
