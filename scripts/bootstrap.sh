#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

parse_dry_run "$@"
require_config KUBERNETES_MINOR KUBERNETES_VERSION CONTROL_PLANE_ENDPOINT POD_CIDR CNI_MANIFEST_FILE
NODE_ROLE="${POSITIONAL_ARGS[0]:-${NODE_ROLE:-control-plane}}"
[[ "$NODE_ROLE" == control-plane || "$NODE_ROLE" == worker ]] || die 'Usage: bootstrap.sh [--dry-run] control-plane|worker'
CNI_MANIFEST_PATH="$CNI_MANIFEST_FILE"
[[ "$CNI_MANIFEST_PATH" = /* ]] || CNI_MANIFEST_PATH="$ROOT_DIR/$CNI_MANIFEST_PATH"

if [[ "$DRY_RUN" == true ]]; then
  log "DRY RUN: bootstrap ${NODE_ROLE} on Ubuntu"
  log 'Would install containerd, kubelet, kubeadm, and kubectl.'
  log "Would configure Kubernetes ${KUBERNETES_VERSION} from the v${KUBERNETES_MINOR} package repository."
  log 'Would disable swap, configure kernel networking, and enable the containerd and kubelet services.'
  if [[ "$NODE_ROLE" == control-plane ]]; then
    log "Would initialize the API endpoint ${CONTROL_PLANE_ENDPOINT}, apply local CNI template ${CNI_MANIFEST_PATH}, and create join credentials."
  else
    log 'Would execute the supplied worker JOIN_COMMAND and register this node with the cluster.'
  fi
  exit 0
fi

require_root
assert_ubuntu
[[ -f "$CNI_MANIFEST_PATH" ]] || die "Missing local CNI manifest: ${CNI_MANIFEST_PATH}. Run scripts/download-templates.sh first."

prepare_node
install_node_packages
configure_containerd

if [[ "$NODE_ROLE" == control-plane ]]; then
  if [[ -f /etc/kubernetes/admin.conf ]]; then
    log 'This control plane is already initialized; nothing to do.'
    exit 0
  fi
  if [[ -n "${JOIN_COMMAND:-}" ]]; then
    bash -c "$JOIN_COMMAND"
    exit 0
  fi
  kubeadm init \
    --control-plane-endpoint "$CONTROL_PLANE_ENDPOINT" \
    --upload-certs \
    --pod-network-cidr "$POD_CIDR" \
    --service-cidr "${SERVICE_CIDR:-10.96.0.0/12}" \
    --kubernetes-version "$KUBERNETES_VERSION"
  mkdir -p "$HOME/.kube"
  cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
  chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  kubectl apply -f "$CNI_MANIFEST_PATH"
  kubeadm token create --print-join-command > /root/worker-join-command.txt
  kubeadm init phase upload-certs --upload-certs > /root/control-plane-certificate-key.txt
  log 'Cluster initialized. Worker join command: /root/worker-join-command.txt'
  log 'Create additional control planes with kubeadm join using the certificate key in /root/control-plane-certificate-key.txt.'
else
  [[ -n "${JOIN_COMMAND:-}" ]] || die 'Set JOIN_COMMAND to the command printed by the first control plane.'
  bash -c "$JOIN_COMMAND"
fi