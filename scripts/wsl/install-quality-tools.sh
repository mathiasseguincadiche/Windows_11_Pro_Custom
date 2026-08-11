#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "[ERREUR] Lance ce script avec ton utilisateur WSL, pas root." >&2
  exit 1
fi

for cmd in curl sha256sum tar unzip gh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERREUR] Commande requise absente: $cmd" >&2
    exit 1
  fi
done

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

verify_sha256() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(sha256sum "$file" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "[ERREUR] SHA256 inattendu pour $(basename "$file")" >&2
    echo "attendu=$expected" >&2
    echo "obtenu =$actual" >&2
    exit 1
  fi
}

log() { printf '\n==> %s\n' "$*"; }

log "terraform-docs"
TERRAFORM_DOCS_VERSION="v0.24.0"
TERRAFORM_DOCS_SHA256="9005daf969de0b50134493a2c00078b49f5f5b39d021cda7c89bf4d4f3d776d3"
terraform_docs_archive="$tmpdir/terraform-docs.tar.gz"
curl -fsSL "https://terraform-docs.io/dl/${TERRAFORM_DOCS_VERSION}/terraform-docs-${TERRAFORM_DOCS_VERSION}-linux-amd64.tar.gz" -o "$terraform_docs_archive"
verify_sha256 "$terraform_docs_archive" "$TERRAFORM_DOCS_SHA256"
tar -xzf "$terraform_docs_archive" -C "$tmpdir" terraform-docs
sudo install -m 0755 "$tmpdir/terraform-docs" /usr/local/bin/terraform-docs

log "actionlint"
ACTIONLINT_VERSION="1.7.12"
ACTIONLINT_SHA256="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
actionlint_archive="$tmpdir/actionlint.tar.gz"
curl -fsSL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" -o "$actionlint_archive"
verify_sha256 "$actionlint_archive" "$ACTIONLINT_SHA256"
tar -xzf "$actionlint_archive" -C "$tmpdir" actionlint
sudo install -m 0755 "$tmpdir/actionlint" /usr/local/bin/actionlint

log "yq"
YQ_VERSION="v4.53.3"
YQ_CHECKSUMS_SHA256="ad5c55be2e571c806fdcf8366d1b2392c2ee92769096a0ec76a1058a72263ae4"
yq_binary="$tmpdir/yq_linux_amd64"
yq_checksums="$tmpdir/yq-checksums"
curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -o "$yq_binary"
curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/checksums" -o "$yq_checksums"
verify_sha256 "$yq_checksums" "$YQ_CHECKSUMS_SHA256"
yq_expected="$(awk '$2 == "yq_linux_amd64" {print $1; exit}' "$yq_checksums")"
if [[ -z "$yq_expected" ]]; then
  echo '[ERREUR] Empreinte yq_linux_amd64 absente du fichier checksums.' >&2
  exit 1
fi
verify_sha256 "$yq_binary" "$yq_expected"
sudo install -m 0755 "$yq_binary" /usr/local/bin/yq

log "TFLint avec vérification GitHub Artifact Attestations"
(
  cd "$tmpdir"
  curl -fsSLO https://github.com/terraform-linters/tflint/releases/latest/download/tflint_linux_amd64.zip
  curl -fsSLO https://github.com/terraform-linters/tflint/releases/latest/download/checksums.txt
  gh attestation verify checksums.txt -R terraform-linters/tflint
  sha256sum --ignore-missing -c checksums.txt
  unzip -oq tflint_linux_amd64.zip
  sudo install -m 0755 tflint /usr/local/bin/tflint
)

printf '\n[OK] Outils qualité IaC installés.\n'
terraform-docs --version
actionlint -version
yq --version
tflint --version
