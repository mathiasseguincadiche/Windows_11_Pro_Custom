#!/usr/bin/env bash
set -Eeuo pipefail

MODE='verify'
TARGET_USER=''

if [[ $# -gt 0 && "$1" != --* ]]; then
  MODE="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-user)
      [[ $# -ge 2 ]] || { echo '[ERREUR] --target-user exige une valeur.' >&2; exit 2; }
      TARGET_USER="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [verify|apply] [--target-user <utilisateur-linux>]"
      exit 0
      ;;
    *)
      echo "[ERREUR] Argument inconnu: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$MODE" != 'verify' && "$MODE" != 'apply' ]]; then
  echo "[ERREUR] Mode invalide: $MODE (verify|apply attendu)." >&2
  exit 2
fi

if [[ -z "$TARGET_USER" ]]; then
  TARGET_USER="$(id -un)"
fi
if [[ ! "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ || "$TARGET_USER" == 'root' ]]; then
  echo "[ERREUR] Utilisateur Linux normal requis: ${TARGET_USER:-<absent>}." >&2
  exit 1
fi
if ! getent passwd "$TARGET_USER" >/dev/null; then
  echo "[ERREUR] Utilisateur Linux absent: $TARGET_USER" >&2
  exit 1
fi
if [[ "$MODE" == 'apply' && ${EUID} -ne 0 ]]; then
  echo '[ERREUR] La convergence/migration des racines WSL doit être lancée via root WSL.' >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo '[ERREUR] jq est requis pour lire le contrat runtime WSL.' >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
RUNTIME_CONTRACT="$REPO_ROOT/config/wsl/runtime-contract.json"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"

if [[ ! -r "$RUNTIME_CONTRACT" ]]; then
  echo "[ERREUR] Contrat runtime WSL absent: $RUNTIME_CONTRACT" >&2
  exit 1
fi
if [[ -z "$TARGET_HOME" || "$TARGET_HOME" != /* || ! -d "$TARGET_HOME" ]]; then
  echo "[ERREUR] HOME Linux invalide pour $TARGET_USER: ${TARGET_HOME:-<absent>}" >&2
  exit 1
fi

resolve_managed_root() {
  local declared="$1"
  local relative=''
  local segment=''

  if [[ "$declared" != '~/'* || ${#declared} -le 2 ]]; then
    echo "[ERREUR] Racine gérée invalide: $declared" >&2
    return 1
  fi

  # IMPORTANT: ne pas utiliser ${declared#~/}. Dans Bash, le '~' du motif
  # peut subir une expansion de tilde et laisser la chaîne '~/...' intacte.
  # Le contrat impose déjà le préfixe '~/'; retirer exactement ses 2 caractères.
  relative="${declared:2}"
  IFS='/' read -r -a segments <<< "$relative"
  for segment in "${segments[@]}"; do
    if [[ -z "$segment" || "$segment" == '.' || "$segment" == '..' ]]; then
      echo "[ERREUR] Segment de racine gérée interdit dans $declared" >&2
      return 1
    fi
  done

  printf '%s/%s\n' "${TARGET_HOME%/}" "$relative"
}

managed_roots_raw="$(jq -er '
  [(.workingRoots // []), (.utilityRoots // [])]
  | add
  | if type == "array"
       and length > 0
       and all(.[]; type == "string" and startswith("~/") and length > 2)
    then .[]
    else error("workingRoots/utilityRoots invalides")
    end
' "$RUNTIME_CONTRACT")" || {
  echo '[ERREUR] Contrat WSL invalide: workingRoots/utilityRoots.' >&2
  exit 1
}
mapfile -t managed_roots <<< "$managed_roots_raw"

forbidden_roots_raw="$(jq -er '
  .forbiddenRoots
  | if type == "array"
       and length > 0
       and all(.[]; type == "string" and startswith("/") and length > 1)
    then .[]
    else error("forbiddenRoots invalide")
    end
' "$RUNTIME_CONTRACT")" || {
  echo '[ERREUR] Contrat WSL invalide: forbiddenRoots.' >&2
  exit 1
}
mapfile -t forbidden_roots <<< "$forbidden_roots_raw"

failed=0
migrated=0
created=0
legacy_base="${TARGET_HOME%/}/~"

for declared_root in "${managed_roots[@]}"; do
  target="$(resolve_managed_root "$declared_root")" || { failed=$((failed + 1)); continue; }
  relative="${declared_root:2}"
  legacy="$legacy_base/$relative"

  for forbidden in "${forbidden_roots[@]}"; do
    if [[ "$target" == "$forbidden" || "$target" == "$forbidden/"* ]]; then
      echo "[KO] Racine gérée sous un montage Windows interdit: $target" >&2
      failed=$((failed + 1))
    fi
  done

  if [[ "$MODE" == 'apply' && ( -e "$legacy" || -L "$legacy" ) ]]; then
    if [[ -L "$legacy" || ! -d "$legacy" ]]; then
      echo "[ERREUR] Ancienne racine malformée non migrable automatiquement: $legacy" >&2
      failed=$((failed + 1))
      continue
    fi

    legacy_has_content=0
    if find "$legacy" -mindepth 1 -print -quit | grep -q .; then legacy_has_content=1; fi

    if [[ -e "$target" || -L "$target" ]]; then
      if [[ -L "$target" || ! -d "$target" ]]; then
        echo "[ERREUR] Cible de racine gérée non sûre: $target" >&2
        failed=$((failed + 1))
        continue
      fi
      target_has_content=0
      if find "$target" -mindepth 1 -print -quit | grep -q .; then target_has_content=1; fi

      if (( legacy_has_content == 1 && target_has_content == 1 )); then
        echo "[ERREUR] Migration automatique refusée: $legacy et $target contiennent tous deux des données. Aucune donnée n'a été supprimée." >&2
        failed=$((failed + 1))
        continue
      fi

      if (( target_has_content == 0 )); then
        rmdir "$target"
        mv -- "$legacy" "$target"
        migrated=$((migrated + 1))
        echo "[FAIT] Racine héritée corrigée: $legacy -> $target"
      else
        rmdir "$legacy"
        migrated=$((migrated + 1))
        echo "[FAIT] Ancienne racine vide retirée: $legacy"
      fi
    else
      mv -- "$legacy" "$target"
      migrated=$((migrated + 1))
      echo "[FAIT] Racine héritée corrigée: $legacy -> $target"
    fi
  fi

  if [[ "$MODE" == 'apply' ]]; then
    if [[ ! -d "$target" ]]; then
      install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$target"
      created=$((created + 1))
      echo "[FAIT] Racine Linux créée: $target"
    fi
    chown "$TARGET_USER:$TARGET_GROUP" "$target"
    chmod 0755 "$target"
  fi

  if [[ ! -d "$target" || -L "$target" ]]; then
    echo "[KO] Répertoire Linux géré absent ou non sûr: $target" >&2
    failed=$((failed + 1))
    continue
  fi
  if [[ -e "$legacy" || -L "$legacy" ]]; then
    echo "[KO] Ancienne racine malformée encore présente: $legacy" >&2
    failed=$((failed + 1))
  fi

  owner="$(stat -c '%U' "$target" 2>/dev/null || true)"
  if [[ "$owner" != "$TARGET_USER" ]]; then
    echo "[KO] Propriétaire inattendu pour $target: ${owner:-inconnu}; attendu=$TARGET_USER" >&2
    failed=$((failed + 1))
  fi

  fs_type="$(findmnt -T "$target" -n -o FSTYPE 2>/dev/null || true)"
  if [[ "$fs_type" != ext4* ]]; then
    echo "[KO] Racine Linux gérée hors ext4: $target (${fs_type:-inconnu})" >&2
    failed=$((failed + 1))
  else
    echo "[OK] $declared_root -> $target ($fs_type, owner=$owner)"
  fi
done

if [[ "$MODE" == 'apply' && -d "$legacy_base" && ! -L "$legacy_base" ]]; then
  if rmdir "$legacy_base" 2>/dev/null; then
    echo "[FAIT] Conteneur hérité '$legacy_base' supprimé car vide."
  else
    echo "[AVERTISSEMENT] '$legacy_base' contient encore des éléments non gérés; aucune suppression automatique n'est effectuée." >&2
  fi
fi

if (( failed > 0 )); then
  echo "VERDICT: WSL MANAGED ROOTS KO ($failed contrôle(s) en échec)" >&2
  exit 1
fi

if [[ "$MODE" == 'apply' ]]; then
  echo "VERDICT: WSL MANAGED ROOTS READY (migrées=$migrated créées=$created)"
else
  echo 'VERDICT: WSL MANAGED ROOTS READY'
fi
