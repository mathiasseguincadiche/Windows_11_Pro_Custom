#!/usr/bin/env bash
set -Eeuo pipefail

as_root() {
  if [[ ${EUID} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

for cmd in curl sha256sum tar unzip gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERREUR] Commande requise absente: $cmd" >&2
    exit 1
  fi
done

if [[ ${EUID} -eq 0 ]]; then
  echo '[INFO] Outils qualité exécutés dans la phase système root WSL; aucun prompt sudo requis.'
fi

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

verify_github_attestation_if_authenticated() {
  local file="$1"
  local repository="$2"

  if [[ -n ${GH_TOKEN:-} || -n ${GITHUB_TOKEN:-} ]] || gh auth status >/dev/null 2>&1; then
    gh attestation verify "$file" -R "$repository"
    echo "[OK] Attestation GitHub vérifiée pour $(basename "$file")."
  else
    echo "[AVERTISSEMENT] Authentification GitHub absente: attestation distante ignorée pour $(basename "$file"); la vérification SHA-256 épinglée reste obligatoire et a réussi." >&2
  fi
}

log() { printf '\n==> %s\n' "$*"; }

log "terraform-docs"
TERRAFORM_DOCS_VERSION="v0.24.0"
TERRAFORM_DOCS_SHA256="9005daf969de0b50134493a2c00078b49f5f5b39d021cda7c89bf4d4f3d776d3"
terraform_docs_archive="$tmpdir/terraform-docs.tar.gz"
curl --retry 5 --retry-all-errors -fsSL "https://github.com/terraform-docs/terraform-docs/releases/download/${TERRAFORM_DOCS_VERSION}/terraform-docs-${TERRAFORM_DOCS_VERSION}-linux-amd64.tar.gz" -o "$terraform_docs_archive"
verify_sha256 "$terraform_docs_archive" "$TERRAFORM_DOCS_SHA256"
tar -xzf "$terraform_docs_archive" -C "$tmpdir" terraform-docs
as_root install -m 0755 "$tmpdir/terraform-docs" /usr/local/bin/terraform-docs

log "actionlint"
ACTIONLINT_VERSION="1.7.12"
ACTIONLINT_SHA256="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
actionlint_archive="$tmpdir/actionlint.tar.gz"
curl --retry 5 --retry-all-errors -fsSL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" -o "$actionlint_archive"
verify_sha256 "$actionlint_archive" "$ACTIONLINT_SHA256"
verify_github_attestation_if_authenticated "$actionlint_archive" 'rhysd/actionlint'
tar -xzf "$actionlint_archive" -C "$tmpdir" actionlint
as_root install -m 0755 "$tmpdir/actionlint" /usr/local/bin/actionlint

log "yq"
YQ_VERSION="v4.53.3"
yq_binary="$tmpdir/yq_linux_amd64"
yq_release="$tmpdir/yq-release.json"
curl --retry 5 --retry-all-errors -fsSL \
  "https://api.github.com/repos/mikefarah/yq/releases/tags/${YQ_VERSION}" \
  -o "$yq_release"
if [[ "$(jq -r '.immutable // false' "$yq_release")" != "true" ]]; then
  echo "[ERREUR] La release yq ${YQ_VERSION} n'est pas marquée immutable par GitHub." >&2
  exit 1
fi
yq_expected="$(jq -r '
  .assets[]
  | select(.name == "yq_linux_amd64")
  | .digest
  | select(type == "string" and startswith("sha256:"))
  | sub("^sha256:"; "")
' "$yq_release" | head -n 1)"
if [[ ! "$yq_expected" =~ ^[0-9a-f]{64}$ ]]; then
  echo '[ERREUR] Digest SHA256 GitHub invalide ou absent pour yq_linux_amd64.' >&2
  exit 1
fi
curl --retry 5 --retry-all-errors -fsSL \
  "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
  -o "$yq_binary"
verify_sha256 "$yq_binary" "$yq_expected"
as_root install -m 0755 "$yq_binary" /usr/local/bin/yq

log "TFLint v0.64.0 avec checksum signé/attestation optionnelle"
TFLINT_VERSION="v0.64.0"
TFLINT_CHECKSUMS_SHA256="07496dc0ab06a39fa718a9f8e471112b6e6ab4fd3a9f1024210a55fe3f1a9ff9"
tflint_archive="$tmpdir/tflint_linux_amd64.zip"
tflint_checksums="$tmpdir/checksums.txt"
curl --retry 5 --retry-all-errors -fsSL "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/tflint_linux_amd64.zip" -o "$tflint_archive"
curl --retry 5 --retry-all-errors -fsSL "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/checksums.txt" -o "$tflint_checksums"
verify_sha256 "$tflint_checksums" "$TFLINT_CHECKSUMS_SHA256"
verify_github_attestation_if_authenticated "$tflint_checksums" 'terraform-linters/tflint'
(
  cd "$tmpdir"
  sha256sum --ignore-missing -c checksums.txt
  unzip -oq tflint_linux_amd64.zip
  as_root install -m 0755 tflint /usr/local/bin/tflint
)

printf '\n[OK] Outils qualité IaC installés.\n'
terraform-docs --version
actionlint -version
yq --version
tflint --version
