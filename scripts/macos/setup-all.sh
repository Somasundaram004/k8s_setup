#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${ROOT_DIR}/cluster.env}"
[[ -f "$CONFIG_FILE" ]] || { printf 'Missing %s; copy .env.example first.\n' "$CONFIG_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG_FILE"

DRY_RUN=false
for argument in "$@"; do
  [[ "$argument" == --dry-run ]] && DRY_RUN=true
done
REMOTE_USER="${REMOTE_USER:-ubuntu}"
[[ -n "${CONTROL_PLANE_HOSTS:-}" ]] || { printf 'Set CONTROL_PLANE_HOSTS as comma-separated hostnames.\n' >&2; exit 1; }
[[ -n "${WORKER_HOSTS:-}" ]] || { printf 'Set WORKER_HOSTS as comma-separated hostnames.\n' >&2; exit 1; }
IFS=',' read -r -a control_planes <<< "$CONTROL_PLANE_HOSTS"
IFS=',' read -r -a workers <<< "$WORKER_HOSTS"

if [[ "$DRY_RUN" == true ]]; then
  printf 'DRY RUN: end-to-end cluster setup as %s\n' "$REMOTE_USER"
  printf 'Control planes: %s\n' "$CONTROL_PLANE_HOSTS"
  printf 'Workers: %s\n' "$WORKER_HOSTS"
  printf 'Would use local templates, bootstrap the first control plane, install prerequisites, join all nodes, install the platform kit, and run health checks.\n'
  printf 'No SSH, package installation, join, Helm, or Kubernetes mutation will occur.\n'
  exit 0
fi

command -v ssh >/dev/null 2>&1 || { printf 'ssh is required on macOS.\n' >&2; exit 1; }
if [[ ! -f "$ROOT_DIR/templates/calico.yaml" ]]; then
  CONFIG_FILE="$CONFIG_FILE" bash "$SCRIPT_DIR/download-templates.sh"
fi
[[ -f "$ROOT_DIR/templates/argocd-values.yaml" && -f "$ROOT_DIR/templates/kube-prometheus-stack-values.yaml" && -f "$ROOT_DIR/templates/metrics-server-values.yaml" ]] || { printf 'Platform templates are missing.\n' >&2; exit 1; }

run_remote() {
  REMOTE_USER="$REMOTE_USER" CONFIG_FILE="$CONFIG_FILE" "$SCRIPT_DIR/macos/remote.sh" "$@"
}

first_control_plane="${control_planes[0]// /}"
run_remote bootstrap control-plane "$first_control_plane"
first_remote="${REMOTE_USER}@${first_control_plane}"
worker_join="$(ssh "$first_remote" 'sudo cat /root/worker-join-command.txt' | tr -d '\r\n')"
control_plane_join_base="$(ssh "$first_remote" 'sudo kubeadm token create --print-join-command' | tr -d '\r\n')"
certificate_key="$(ssh "$first_remote" 'sudo kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1' | tr -d '\r\n')"
[[ "$certificate_key" =~ ^[a-f0-9]{64}$ ]] || { printf 'Could not obtain the control-plane certificate key.\n' >&2; exit 1; }
control_plane_join="${control_plane_join_base} --control-plane --certificate-key ${certificate_key}"

for host in "${control_planes[@]:1}"; do
  host="${host// /}"
  JOIN_COMMAND="$control_plane_join" run_remote bootstrap control-plane "$host"
done
for host in "${workers[@]}"; do
  host="${host// /}"
  JOIN_COMMAND="$worker_join" run_remote bootstrap worker "$host"
done

remote_dir="/tmp/k8s-setup"
ssh "$first_remote" "sudo bash '$remote_dir/scripts/install-helm.sh'"
run_remote platform cluster "$first_control_plane"
run_remote health control-plane "$first_control_plane"
printf 'End-to-end setup completed.\n'