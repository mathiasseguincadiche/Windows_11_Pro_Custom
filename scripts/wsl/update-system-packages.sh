#!/usr/bin/env bash
set -Eeuo pipefail

mode="${1:-audit}"
case "$mode" in
  audit|apply|verify) ;;
  *) echo "Usage: $0 {audit|apply|verify}" >&2; exit 2 ;;
esac

if [[ ${EUID} -eq 0 ]]; then
  echo '[ERREUR] Lance ce script avec ton utilisateur WSL, pas root.' >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo '[ERREUR] /etc/os-release introuvable.' >&2
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release
if [[ ${ID:-} != ubuntu || ${VERSION_ID:-} != 26.04 ]]; then
  echo "[ERREUR] Ubuntu 26.04 est attendu. Détecté: ${ID:-?} ${VERSION_ID:-?}." >&2
  exit 1
fi

refresh_indexes() {
  echo '[ANALYSE] Actualisation des catalogues APT (aucun paquet installé à cette étape).'
  sudo apt-get update -qq
}

pending_lines() {
  sudo apt-get -s upgrade --with-new-pkgs 2>/dev/null | awk '/^Inst / {print}'
}

pending_count() {
  local count
  count="$(pending_lines | wc -l)"
  printf '%s' "$count"
}

refresh_indexes
count="$(pending_count)"

if (( count == 0 )); then
  echo '[DÉJÀ OK] Ubuntu 26.04 et les dépôts APT configurés ne proposent aucun paquet à mettre à jour.'
else
  echo "[À FAIRE] ${count} paquet(s) APT peuvent être mis à jour:"
  pending_lines | sed 's/^/  /'
fi

if [[ "$mode" == audit ]]; then
  exit 0
fi

if [[ "$mode" == verify ]]; then
  if (( count > 0 )); then
    echo "[ERREUR] ${count} paquet(s) APT restent à mettre à jour." >&2
    exit 1
  fi
  if [[ -e /var/run/reboot-required ]]; then
    echo '[ACTION REQUISE] Ubuntu signale un redémarrage requis. Sous WSL, ferme ensuite WSL avec wsl.exe --shutdown depuis Windows.'
  fi
  exit 0
fi

if (( count == 0 )); then
  echo '[DÉJÀ OK] Aucun paquet Ubuntu à installer.'
  exit 0
fi

echo '[EN COURS] Mise à jour APT sûre: upgrade --with-new-pkgs, sans dist-upgrade ni autoremove.'
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y --with-new-pkgs

refresh_indexes
remaining="$(pending_count)"
if (( remaining > 0 )); then
  echo "[ERREUR] ${remaining} paquet(s) APT restent à mettre à jour après Apply." >&2
  pending_lines | sed 's/^/  /' >&2
  exit 1
fi

if [[ -e /var/run/reboot-required ]]; then
  echo '[ACTION REQUISE] Ubuntu signale un redémarrage requis. Aucun shutdown automatique n’est effectué par ce script.'
fi

echo '[FAIT] Paquets Ubuntu 26.04 mis à jour et revalidés.'
