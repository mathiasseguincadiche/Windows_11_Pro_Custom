#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_USER=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-user)
      [[ $# -ge 2 ]] || { echo '[ERREUR] --target-user exige une valeur.' >&2; exit 2; }
      TARGET_USER="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 --target-user <utilisateur-linux>"
      exit 0
      ;;
    *)
      echo "[ERREUR] Argument inconnu: $1" >&2
      exit 2
      ;;
  esac
done

if [[ ${EUID} -ne 0 ]]; then
  echo '[ERREUR] Ce bootstrap système doit être lancé par l orchestrateur avec le compte root WSL.' >&2
  echo 'Il ne demande ni ne stocke le mot de passe sudo de l utilisateur cible.' >&2
  exit 1
fi

if [[ ! "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "[ERREUR] Utilisateur cible Linux invalide: ${TARGET_USER:-<absent>}" >&2
  exit 1
fi
if ! getent passwd "$TARGET_USER" >/dev/null; then
  echo "[ERREUR] Utilisateur cible Linux absent: $TARGET_USER" >&2
  exit 1
fi
if [[ "$TARGET_USER" == 'root' ]]; then
  echo '[ERREUR] root ne peut pas être l utilisateur DevOps cible.' >&2
  exit 1
fi
if ! command -v runuser >/dev/null 2>&1; then
  echo '[ERREUR] runuser est requis pour les opérations appartenant à l utilisateur cible.' >&2
  exit 1
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
  echo "[ERREUR] HOME Linux invalide pour $TARGET_USER: ${TARGET_HOME:-<absent>}" >&2
  exit 1
fi

run_as_target() {
  runuser -u "$TARGET_USER" -- env \
    HOME="$TARGET_HOME" \
    USER="$TARGET_USER" \
    LOGNAME="$TARGET_USER" \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "$@"
}

if [[ ! -r /etc/os-release ]]; then
  echo "[ERREUR] /etc/os-release introuvable." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
DOCKER_DAEMON_CONFIG="$REPO_ROOT/config/wsl/docker-daemon.json"
VERSIONS_FILE="$REPO_ROOT/config/devops/tool-versions.env"
RUNTIME_CONTRACT="$REPO_ROOT/config/wsl/runtime-contract.json"
MANAGED_ROOTS_SCRIPT="$SCRIPT_DIR/manage-wsl-roots.sh"

# shellcheck disable=SC1091
source /etc/os-release
if [[ ${ID:-} != "ubuntu" ]]; then
  echo "[ERREUR] Ubuntu WSL2 est attendu. Distribution détectée: ${ID:-inconnue}." >&2
  exit 1
fi

if [[ ! -r "$DOCKER_DAEMON_CONFIG" ]]; then
  echo "[ERREUR] Configuration Docker absente: $DOCKER_DAEMON_CONFIG" >&2
  exit 1
fi

if [[ ! -r "$VERSIONS_FILE" ]]; then
  echo "[ERREUR] Matrice de versions DevOps absente: $VERSIONS_FILE" >&2
  exit 1
fi

if [[ ! -r "$RUNTIME_CONTRACT" ]]; then
  echo "[ERREUR] Contrat runtime WSL absent: $RUNTIME_CONTRACT" >&2
  exit 1
fi
if [[ ! -r "$MANAGED_ROOTS_SCRIPT" ]]; then
  echo "[ERREUR] Gestionnaire de racines WSL absent: $MANAGED_ROOTS_SCRIPT" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$VERSIONS_FILE"
: "${KUBECTL_VERSION:?KUBECTL_VERSION absent}"
: "${HELM_VERSION:?HELM_VERSION absent}"
: "${TERRAFORM_VERSION:?TERRAFORM_VERSION absent}"
: "${AWS_CLI_VERSION:?AWS_CLI_VERSION absent}"
: "${MINIKUBE_VERSION:?MINIKUBE_VERSION absent}"
: "${KIND_VERSION:?KIND_VERSION absent}"

ARCH="$(dpkg --print-architecture)"
if [[ ${ARCH} != "amd64" ]]; then
  echo "[ERREUR] Cette machine cible AMD64. Architecture détectée: ${ARCH}." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
install -m 0755 -d /etc/apt/keyrings
install -m 0755 -d /etc/apt/sources.list.d

log() { printf '\n==> %s\n' "$*"; }
curl_retry() { curl --retry 5 --retry-all-errors --connect-timeout 15 "$@"; }

log "Contexte d élévation"
echo "[OK] Phase système exécutée comme root WSL sans prompt sudo; utilisateur cible=$TARGET_USER home=$TARGET_HOME"

log "Paquets de base"
apt-get update
apt-get install -y \
  ca-certificates curl wget gnupg dirmngr lsb-release unzip jq git openssh-client rsync tar gzip \
  python3 python3-pip python3-venv pipx shellcheck shfmt ansible-core bash-completion

log "Docker Engine + Buildx + Compose depuis le dépôt Docker officiel"
for pkg in docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc; do
  apt-get remove -y "$pkg" >/dev/null 2>&1 || true
done
curl_retry -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/windows11-pro-custom-docker.asc
install -m 0644 /tmp/windows11-pro-custom-docker.asc /etc/apt/keyrings/docker.asc
rm -f /tmp/windows11-pro-custom-docker.asc
tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
install -m 0755 -d /etc/docker
install -m 0644 "$DOCKER_DAEMON_CONFIG" /etc/docker/daemon.json
systemctl enable --now docker
systemctl restart docker
usermod -aG docker "$TARGET_USER"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

log "kubectl ${KUBECTL_VERSION} avec checksum upstream"
curl_retry -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o "$tmpdir/kubectl"
curl_retry -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" -o "$tmpdir/kubectl.sha256"
echo "$(cat "$tmpdir/kubectl.sha256")  $tmpdir/kubectl" | sha256sum -c -
install -m 0755 "$tmpdir/kubectl" /usr/local/bin/kubectl

log "Helm ${HELM_VERSION} avec checksum upstream"
helm_archive="helm-${HELM_VERSION}-linux-amd64.tar.gz"
curl_retry -fsSL "https://get.helm.sh/${helm_archive}" -o "$tmpdir/$helm_archive"
curl_retry -fsSL "https://get.helm.sh/${helm_archive}.sha256sum" -o "$tmpdir/$helm_archive.sha256sum"
helm_sha="$(awk '{print $1}' "$tmpdir/$helm_archive.sha256sum")"
echo "$helm_sha  $tmpdir/$helm_archive" | sha256sum -c -
tar -xzf "$tmpdir/$helm_archive" -C "$tmpdir"
install -m 0755 "$tmpdir/linux-amd64/helm" /usr/local/bin/helm

log "Terraform ${TERRAFORM_VERSION} avec checksum HashiCorp"
terraform_archive="terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
curl_retry -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${terraform_archive}" -o "$tmpdir/$terraform_archive"
curl_retry -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" -o "$tmpdir/terraform_SHA256SUMS"
(
  cd "$tmpdir"
  grep " ${terraform_archive}$" terraform_SHA256SUMS | sha256sum -c -
  unzip -qo "$terraform_archive"
)
install -m 0755 "$tmpdir/terraform" /usr/local/bin/terraform

log "GitHub CLI depuis le dépôt officiel"
curl_retry -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | tee /etc/apt/sources.list.d/github-cli.list >/dev/null

log "Trivy depuis le dépôt officiel Aqua Security"
wget -qO- https://aquasecurity.github.io/trivy-repo/deb/public.key \
  | gpg --dearmor | tee /usr/share/keyrings/trivy.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
  | tee /etc/apt/sources.list.d/trivy.list >/dev/null

apt-get update
apt-get install -y gh trivy

log "AWS CLI v2 ${AWS_CLI_VERSION} avec signature PGP officielle"
aws_archive="awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip"
aws_zip="$tmpdir/awscliv2.zip"
aws_sig="$tmpdir/awscliv2.sig"
aws_gnupg="$tmpdir/aws-gnupg"
aws_fingerprint='FB5DB77FD5C118B80511ADA8A6310ACC4672475C'
install -m 0700 -d "$aws_gnupg"
curl_retry -fsSL "https://awscli.amazonaws.com/${aws_archive}" -o "$aws_zip"
curl_retry -fsSL "https://awscli.amazonaws.com/${aws_archive}.sig" -o "$aws_sig"

aws_key_loaded=0
for keyserver in hkps://keyserver.ubuntu.com hkps://keys.openpgp.org; do
  for attempt in 1 2 3; do
    if gpg --batch --homedir "$aws_gnupg" --keyserver-options timeout=15 --keyserver "$keyserver" --recv-keys "$aws_fingerprint"; then
      aws_key_loaded=1
      break 2
    fi
    echo "[AVERTISSEMENT] Clé AWS non récupérée depuis $keyserver (tentative $attempt/3)." >&2
    sleep $((attempt * 2))
  done
done
if [[ $aws_key_loaded -ne 1 ]]; then
  echo '[ERREUR] Impossible de récupérer la clé publique AWS après retries sur les keyservers autorisés.' >&2
  exit 1
fi

aws_imported_fingerprint="$(gpg --batch --homedir "$aws_gnupg" --with-colons --fingerprint "$aws_fingerprint" | awk -F: '$1 == "fpr" { print $10; exit }')"
if [[ "$aws_imported_fingerprint" != "$aws_fingerprint" ]]; then
  echo "[ERREUR] Empreinte de clé AWS CLI inattendue: ${aws_imported_fingerprint:-absente}" >&2
  exit 1
fi
gpg --batch --homedir "$aws_gnupg" --verify "$aws_sig" "$aws_zip"
unzip -q "$aws_zip" -d "$tmpdir/aws-cli"
if command -v aws >/dev/null 2>&1; then
  "$tmpdir/aws-cli/aws/install" --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
else
  "$tmpdir/aws-cli/aws/install" --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli
fi

log "Minikube ${MINIKUBE_VERSION} avec checksum upstream"
minikube_url="https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-linux-amd64"
curl_retry -fsSL "$minikube_url" -o "$tmpdir/minikube"
curl_retry -fsSL "${minikube_url}.sha256" -o "$tmpdir/minikube.sha256"
echo "$(cat "$tmpdir/minikube.sha256")  $tmpdir/minikube" | sha256sum -c -
install -m 0755 "$tmpdir/minikube" /usr/local/bin/minikube

log "kind ${KIND_VERSION} avec checksum upstream"
kind_url="https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
curl_retry -fsSL "$kind_url" -o "$tmpdir/kind-linux-amd64"
curl_retry -fsSL "${kind_url}.sha256sum" -o "$tmpdir/kind-linux-amd64.sha256sum"
(
  cd "$tmpdir"
  sha256sum -c kind-linux-amd64.sha256sum
)
install -m 0755 "$tmpdir/kind-linux-amd64" /usr/local/bin/kind

log "Outils qualité IaC (complément non bloquant)"
if bash "$SCRIPT_DIR/install-quality-tools.sh"; then
  echo '[OK] Outils qualité IaC installés.'
else
  echo "[AVERTISSEMENT] Les outils qualité additionnels n ont pas tous pu être installés. La stack DevOps cœur continue; relance le composant plus tard." >&2
fi

log "Profil shell DevOps (complément non bloquant)"
if run_as_target bash "$SCRIPT_DIR/manage-shell-profile.sh" apply; then
  echo "[OK] Profil shell DevOps appliqué pour $TARGET_USER."
else
  echo "[AVERTISSEMENT] Profil shell DevOps non appliqué complètement pour $TARGET_USER. Les outils cœur restent installés." >&2
fi

log "Répertoires Linux gérés"
if bash "$MANAGED_ROOTS_SCRIPT" apply --target-user "$TARGET_USER"; then
  echo "[OK] Racines Linux gérées convergées et anciennes formes '~/...' migrées sans perte."
else
  echo '[ERREUR] Impossible de converger les racines Linux gérées sans risque de perte de données.' >&2
  exit 1
fi

log "Contrat runtime des versions épinglées"
kubectl version --client --output=json | jq -e --arg expected "$KUBECTL_VERSION" '.clientVersion.gitVersion == $expected' >/dev/null
helm version --short | grep -F "$HELM_VERSION" >/dev/null
terraform version -json | jq -e --arg expected "$TERRAFORM_VERSION" '.terraform_version == $expected' >/dev/null
aws --version 2>&1 | grep -F "aws-cli/${AWS_CLI_VERSION}" >/dev/null
minikube version --short | grep -F "$MINIKUBE_VERSION" >/dev/null
kind version | grep -F "$KIND_VERSION" >/dev/null

cat <<EOF

[OK] Stack DevOps cœur installée avec versions épinglées et artefacts sensibles vérifiés.

Docker utilise le driver de logs local avec rotation 10 MiB x 3 fichiers par conteneur.
Les versions kubectl, Helm, Terraform, AWS CLI, Minikube et kind sont pilotées par config/devops/tool-versions.env.
AWS CLI est vérifié par signature PGP et kind par checksum SHA-256 upstream avant installation.
Les outils qualité additionnels sont installés au niveau système; le profil shell et les répertoires Linux restent gérés sous l'utilisateur $TARGET_USER.
Aucun mot de passe sudo n'est demandé, transmis ou persisté par ce bootstrap: l'orchestrateur utilise la frontière root native de WSL pour les mutations système.
Important : l'ajout au groupe docker prend effet après ouverture d'une nouvelle session WSL; l orchestrateur gère ce redémarrage de session et revalide Docker sous $TARGET_USER.
EOF
