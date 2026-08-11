#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "[ERREUR] Lance ce script avec ton utilisateur WSL, pas root." >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "[ERREUR] /etc/os-release introuvable." >&2
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release
if [[ ${ID:-} != "ubuntu" ]]; then
  echo "[ERREUR] Ubuntu WSL2 est attendu. Distribution détectée: ${ID:-inconnue}." >&2
  exit 1
fi

ARCH="$(dpkg --print-architecture)"
if [[ ${ARCH} != "amd64" ]]; then
  echo "[ERREUR] Cette machine cible AMD64. Architecture détectée: ${ARCH}." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
sudo install -m 0755 -d /etc/apt/keyrings
sudo install -m 0755 -d /etc/apt/sources.list.d

log() { printf '\n==> %s\n' "$*"; }

log "Paquets de base"
sudo apt-get update
sudo apt-get install -y \
  ca-certificates curl wget gnupg lsb-release unzip jq git openssh-client rsync \
  python3 python3-pip python3-venv pipx shellcheck shfmt ansible-core

log "Docker Engine + Buildx + Compose depuis le dépôt Docker officiel"
for pkg in docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc; do
  sudo apt-get remove -y "$pkg" >/dev/null 2>&1 || true
done
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

log "kubectl depuis pkgs.k8s.io"
KUBERNETES_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
KUBERNETES_MINOR="$(printf '%s' "$KUBERNETES_VERSION" | sed -E 's/^(v[0-9]+\.[0-9]+)\..*$/\1/')"
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBERNETES_MINOR}/deb/Release.key" \
  | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 0644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBERNETES_MINOR}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

log "Helm depuis le dépôt Debian/Ubuntu recommandé par le projet Helm"
HELM_KEY_ID="DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6"
helm_key="$(mktemp)"
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey -o "$helm_key"
actual_helm_key="$(gpg --show-keys --with-colons "$helm_key" | awk -F: '$1 == "fpr" {print $10}' | head -n1)"
if [[ "$actual_helm_key" != "$HELM_KEY_ID" ]]; then
  echo "[ERREUR] Empreinte de clé Helm inattendue: $actual_helm_key" >&2
  rm -f "$helm_key"
  exit 1
fi
gpg --dearmor < "$helm_key" | sudo tee /usr/share/keyrings/helm.gpg >/dev/null
rm -f "$helm_key"
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" \
  | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list >/dev/null

log "Terraform depuis HashiCorp"
wget -qO- https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
ubuntu_codename="${UBUNTU_CODENAME:-$(lsb_release -cs)}"
echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${ubuntu_codename} main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

log "GitHub CLI depuis le dépôt officiel"
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null

log "Trivy depuis le dépôt officiel Aqua Security"
wget -qO- https://aquasecurity.github.io/trivy-repo/deb/public.key \
  | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
  | sudo tee /etc/apt/sources.list.d/trivy.list >/dev/null

sudo apt-get update
sudo apt-get install -y kubectl helm terraform gh trivy

log "AWS CLI v2 depuis l'installateur officiel"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o "$tmpdir/awscliv2.zip"
unzip -q "$tmpdir/awscliv2.zip" -d "$tmpdir"
if command -v aws >/dev/null 2>&1; then
  sudo "$tmpdir/aws/install" --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
else
  sudo "$tmpdir/aws/install" --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli
fi

log "Minikube stable"
curl -fsSL https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64 -o "$tmpdir/minikube"
sudo install -m 0755 "$tmpdir/minikube" /usr/local/bin/minikube

log "kind"
KIND_VERSION="${KIND_VERSION:-v0.32.0}"
curl -fsSL "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64" -o "$tmpdir/kind"
sudo install -m 0755 "$tmpdir/kind" /usr/local/bin/kind

log "Répertoires de travail"
mkdir -p "$HOME"/{projects,labs,repositories,scripts,workspace,backups}

cat <<'EOF'

[OK] Stack DevOps installée.

Important : l'ajout au groupe docker prend effet après ouverture d'une nouvelle session WSL.
Exécute ensuite :
  wsl.exe --shutdown   # depuis Windows
puis relance Ubuntu et :
  ./scripts/wsl/validate-devops.sh
EOF
