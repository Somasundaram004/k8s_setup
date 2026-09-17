#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

parse_dry_run "$@"
require_config KUBERNETES_MINOR KUBERNETES_VERSION
NODE_ROLE="${POSITIONAL_ARGS[0]:-${NODE_ROLE:-}}"
[[ "$NODE_ROLE" == control-plane || "$NODE_ROLE" == worker ]] || die 'Usage: upgrade.sh [--dry-run] control-plane|worker'
if [[ "$DRY_RUN" == true ]]; then
  log "DRY RUN: upgrade ${NODE_ROLE} on $(hostname --short) to ${KUBERNETES_VERSION}"
  log 'Would verify cluster capacity and drain this node while respecting daemonsets and PodDisruptionBudgets.'
  log "Would update kubeadm, kubelet, and kubectl from the v${KUBERNETES_MINOR} repository."
  if [[ "$NODE_ROLE" == control-plane ]]; then
    log 'Would run kubeadm upgrade plan followed by kubeadm upgrade apply.'
  else
    log 'Would run kubeadm upgrade node on the worker.'
  fi
  log 'Would restart kubelet and uncordon the node after the upgrade.'
  exit 0
fi

require_root
assert_ubuntu
require_command kubectl
require_command kubeadm
export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
NODE_NAME="$(hostname --short)"
if [[ "$NODE_ROLE" == worker && ! -f "$KUBECONFIG" ]]; then
  die 'Worker upgrades need an admin kubeconfig to drain and uncordon the node. Set KUBECONFIG to a secured copy.'
fi

if [[ "${ALLOW_DOWNTIME:-false}" != true ]]; then
  ready_nodes="$(kubectl get nodes --no-headers | awk '$2 == "Ready" { count++ } END { print count + 0 }')"
  [[ "$ready_nodes" -ge 2 ]] || die 'At least two Ready nodes are required for a no-downtime upgrade. Set ALLOW_DOWNTIME=true only for development.'
fi

log "Draining ${NODE_NAME}; workloads must have replicas and a PodDisruptionBudget."
kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data --grace-period=60 --timeout=10m
cleanup() { kubectl uncordon "$NODE_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

apt-mark unhold kubeadm kubelet kubectl || true
configure_kubernetes_repository
apt-get update
apt-get install -y kubeadm="${KUBERNETES_VERSION#v}-*"
if [[ "$NODE_ROLE" == control-plane ]]; then
  kubeadm upgrade plan
  kubeadm upgrade apply -y "$KUBERNETES_VERSION"
else
  kubeadm upgrade node
fi
apt-get install -y kubelet="${KUBERNETES_VERSION#v}-*" kubectl="${KUBERNETES_VERSION#v}-*"
apt-mark hold kubelet kubeadm kubectl
systemctl daemon-reload
systemctl restart kubelet
log "${NODE_NAME} upgraded to ${KUBERNETES_VERSION}; it has been uncordoned."