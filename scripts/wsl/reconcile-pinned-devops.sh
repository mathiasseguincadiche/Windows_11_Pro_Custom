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

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
versions_file="$repo_root/config/devops/tool-versions.env"
[[ -r "$versions_file" ]] || { echo "[ERREUR] Matrice de versions absente: $versions_file" >&2; exit 1; }

# shellcheck disable=SC1090
source "$versions_file"
: "${KUBECTL_VERSION:?KUBECTL_VERSION absent}"
: "${HELM_VERSION:?HELM_VERSION absent}"
: "${TERRAFORM_VERSION:?TERRAFORM_VERSION absent}"
: "${AWS_CLI_VERSION:?AWS_CLI_VERSION absent}"
: "${MINIKUBE_VERSION:?MINIKUBE_VERSION absent}"
: "${KIND_VERSION:?KIND_VERSION absent}"

for cmd in curl jq unzip tar sha256sum sudo; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "[ERREUR] Commande requise absente: $cmd" >&2; exit 1; }
done

current_kubectl() { command -v kubectl >/dev/null 2>&1 && kubectl version --client --output=json 2>/dev/null | jq -r '.clientVersion.gitVersion // empty' || true; }
current_helm() { command -v helm >/dev/null 2>&1 && helm version --template '{{.Version}}' 2>/dev/null || true; }
current_terraform() { command -v terraform >/dev/null 2>&1 && terraform version -json 2>/dev/null | jq -r '.terraform_version // empty' || true; }
current_aws() { command -v aws >/dev/null 2>&1 && aws --version 2>&1 | sed -n 's/^aws-cli\/\([^ ]*\).*/\1/p' || true; }
current_minikube() { command -v minikube >/dev/null 2>&1 && minikube version --short 2>/dev/null | tr -d '[:space:]' || true; }
current_kind() { command -v kind >/dev/null 2>&1 && kind version 2>/dev/null | awk '{print $2}' || true; }

expected_names=(kubectl helm terraform aws minikube kind)
expected_versions=("$KUBECTL_VERSION" "$HELM_VERSION" "$TERRAFORM_VERSION" "$AWS_CLI_VERSION" "$MINIKUBE_VERSION" "$KIND_VERSION")
actual_versions=("$(current_kubectl)" "$(current_helm)" "$(current_terraform)" "$(current_aws)" "$(current_minikube)" "$(current_kind)")

mismatches=()
print_state() {
  local i actual expected name
  mismatches=()
  for i in "${!expected_names[@]}"; do
    name="${expected_names[$i]}"
    expected="${expected_versions[$i]}"
    actual="${actual_versions[$i]}"
    [[ -n "$actual" ]] || actual='<absent>'
    if [[ "$actual" == "$expected" ]]; then
      printf '[DÉJÀ OK] %-10s %s\n' "$name" "$actual"
    else
      printf '[À FAIRE] %-10s installé=%s cible-dépôt=%s\n' "$name" "$actual" "$expected"
      mismatches+=("$name")
    fi
  done
}

print_state
if [[ "$mode" == audit ]]; then
  if (( ${#mismatches[@]} == 0 )); then
    echo '[DÉJÀ OK] Tous les outils DevOps épinglés correspondent à tool-versions.env.'
  else
    echo "[À FAIRE] ${#mismatches[@]} outil(s) DevOps doivent converger vers les versions du dépôt."
  fi
  exit 0
fi

if [[ "$mode" == verify ]]; then
  if (( ${#mismatches[@]} > 0 )); then
    echo "[ERREUR] ${#mismatches[@]} outil(s) DevOps ne correspondent pas aux versions épinglées." >&2
    exit 1
  fi
  echo '[DÉJÀ OK] Versions DevOps épinglées validées.'
  exit 0
fi

if (( ${#mismatches[@]} == 0 )); then
  echo '[DÉJÀ OK] Aucun outil DevOps épinglé à modifier.'
  exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

needs() {
  local wanted="$1" item
  for item in "${mismatches[@]}"; do [[ "$item" == "$wanted" ]] && return 0; done
  return 1
}

if needs kubectl; then
  echo "[EN COURS] kubectl $KUBECTL_VERSION"
  curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o "$tmpdir/kubectl"
  curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" -o "$tmpdir/kubectl.sha256"
  echo "$(cat "$tmpdir/kubectl.sha256")  $tmpdir/kubectl" | sha256sum -c -
  sudo install -m 0755 "$tmpdir/kubectl" /usr/local/bin/kubectl
fi

if needs helm; then
  echo "[EN COURS] Helm $HELM_VERSION"
  helm_archive="helm-${HELM_VERSION}-linux-amd64.tar.gz"
  curl -fsSL "https://get.helm.sh/${helm_archive}" -o "$tmpdir/$helm_archive"
  curl -fsSL "https://get.helm.sh/${helm_archive}.sha256sum" -o "$tmpdir/$helm_archive.sha256sum"
  helm_sha="$(awk '{print $1}' "$tmpdir/$helm_archive.sha256sum")"
  echo "$helm_sha  $tmpdir/$helm_archive" | sha256sum -c -
  tar -xzf "$tmpdir/$helm_archive" -C "$tmpdir"
  sudo install -m 0755 "$tmpdir/linux-amd64/helm" /usr/local/bin/helm
fi

if needs terraform; then
  echo "[EN COURS] Terraform $TERRAFORM_VERSION"
  terraform_archive="terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
  curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${terraform_archive}" -o "$tmpdir/$terraform_archive"
  curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" -o "$tmpdir/terraform_SHA256SUMS"
  (
    cd "$tmpdir"
    grep " ${terraform_archive}$" terraform_SHA256SUMS | sha256sum -c -
    unzip -qo "$terraform_archive"
  )
  sudo install -m 0755 "$tmpdir/terraform" /usr/local/bin/terraform
fi

if needs aws; then
  echo "[EN COURS] AWS CLI $AWS_CLI_VERSION"
  aws_archive="awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip"
  curl -fsSL "https://awscli.amazonaws.com/${aws_archive}" -o "$tmpdir/awscliv2.zip"
  unzip -q "$tmpdir/awscliv2.zip" -d "$tmpdir/aws-cli"
  if command -v aws >/dev/null 2>&1; then
    sudo "$tmpdir/aws-cli/aws/install" --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
  else
    sudo "$tmpdir/aws-cli/aws/install" --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli
  fi
fi

if needs minikube; then
  echo "[EN COURS] Minikube $MINIKUBE_VERSION"
  minikube_url="https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-linux-amd64"
  curl -fsSL "$minikube_url" -o "$tmpdir/minikube"
  curl -fsSL "${minikube_url}.sha256" -o "$tmpdir/minikube.sha256"
  echo "$(cat "$tmpdir/minikube.sha256")  $tmpdir/minikube" | sha256sum -c -
  sudo install -m 0755 "$tmpdir/minikube" /usr/local/bin/minikube
fi

if needs kind; then
  echo "[EN COURS] kind $KIND_VERSION"
  kind_url="https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
  curl -fsSL "$kind_url" -o "$tmpdir/kind"
  curl -fsSL "${kind_url}.sha256sum" -o "$tmpdir/kind.sha256sum"
  kind_sha="$(awk '{print $1}' "$tmpdir/kind.sha256sum")"
  echo "$kind_sha  $tmpdir/kind" | sha256sum -c -
  sudo install -m 0755 "$tmpdir/kind" /usr/local/bin/kind
fi

actual_versions=("$(current_kubectl)" "$(current_helm)" "$(current_terraform)" "$(current_aws)" "$(current_minikube)" "$(current_kind)")
print_state
if (( ${#mismatches[@]} > 0 )); then
  echo "[ERREUR] ${#mismatches[@]} outil(s) restent hors cible après Apply." >&2
  exit 1
fi

echo '[FAIT] Outils DevOps réconciliés exclusivement vers les versions épinglées du dépôt.'
