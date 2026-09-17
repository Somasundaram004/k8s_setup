#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${ROOT_DIR}/cluster.env}"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
parse_dry_run() {
  DRY_RUN=false
  POSITIONAL_ARGS=()
  for argument in "$@"; do
    if [[ "$argument" == --dry-run ]]; then
      DRY_RUN=true
    else
      POSITIONAL_ARGS+=("$argument")
    fi
  done
}
require_root() { [[ "$EUID" -eq 0 ]] || die 'Run this script as root or with sudo.'; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }
require_config() {
  local name
  for name in "$@"; do
    [[ -n "${!name:-}" ]] || die "Set ${name} in ${CONFIG_FILE}."
  done
}

assert_ubuntu() {
  [[ -r /etc/os-release ]] || die 'This script supports Ubuntu 22.04 or 24.04.'
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == ubuntu ]] || die 'This script supports Ubuntu 22.04 or 24.04.'
  [[ "${VERSION_ID:-}" == 22.04 || "${VERSION_ID:-}" == 24.04 ]] || die "Unsupported Ubuntu version: ${VERSION_ID:-unknown}"
}

configure_kubernetes_repository() {
  local minor="${KUBERNETES_MINOR#v}"
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${minor}/deb/Release.key" \
    | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  chmod 0644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  printf 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v%s/deb/ /\n' "$minor" \
    > /etc/apt/sources.list.d/kubernetes.list
}

install_node_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl gpg apt-transport-https containerd
  configure_kubernetes_repository
  apt-get update
  apt-get install -y kubelet="${KUBERNETES_VERSION#v}-*" kubeadm="${KUBERNETES_VERSION#v}-*" kubectl="${KUBERNETES_VERSION#v}-*"
  apt-mark hold kubelet kubeadm kubectl
}

configure_containerd() {
  mkdir -p /etc/containerd
  containerd config default > /etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  systemctl enable --now containerd
  systemctl restart containerd
  systemctl enable kubelet
}

prepare_node() {
  swapoff -a
  sed -ri '/\sswap\s/s/^/#/' /etc/fstab
  modprobe overlay
  modprobe br_netfilter
  cat >/etc/modules-load.d/kubernetes.conf <<'EOF'
overlay
br_netfilter
EOF
  cat >/etc/sysctl.d/99-kubernetes-network.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
  sysctl --system >/dev/null
}