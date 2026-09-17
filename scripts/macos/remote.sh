#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${ROOT_DIR}/cluster.env}"
[[ -f "$CONFIG_FILE" ]] || { printf 'Missing %s; copy .env.example first.\n' "$CONFIG_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG_FILE"

DRY_RUN=false
POSITIONAL_ARGS=()
for argument in "$@"; do
  if [[ "$argument" == --dry-run ]]; then
    DRY_RUN=true
  else
    POSITIONAL_ARGS+=("$argument")
  fi
done
ACTION="${POSITIONAL_ARGS[0]:-}"
ROLE="${POSITIONAL_ARGS[1]:-}"
HOST="${POSITIONAL_ARGS[2]:-}"
REMOTE_USER="${REMOTE_USER:-ubuntu}"
[[ "$ACTION" == bootstrap || "$ACTION" == upgrade || "$ACTION" == health ]] || {
  printf 'Usage: %s [--dry-run] bootstrap|upgrade|health control-plane|worker host\n' "$0" >&2
  exit 1
}
[[ -n "$ROLE" && -n "$HOST" ]] || { printf 'Role and host are required.\n' >&2; exit 1; }
[[ "$ACTION" == health || "$ROLE" == control-plane || "$ROLE" == worker ]] || exit 1

if [[ "$DRY_RUN" == true ]]; then
  printf 'DRY RUN: macOS would target %s@%s\n' "$REMOTE_USER" "$HOST"
  case "$ACTION" in
    bootstrap) printf 'Would stage configuration and run Linux bootstrap for the %s role.\n' "$ROLE" ;;
    upgrade) printf 'Would stage configuration and run a rolling %s upgrade, including drain and uncordon.\n' "$ROLE" ;;
    health) printf 'Would run the Kubernetes health check remotely.\n' ;;
  esac
  printf 'No SSH, SCP, package installation, drain, or Kubernetes mutation will occur.\n'
  exit 0
fi

command -v ssh >/dev/null 2>&1 || { printf 'ssh is required.\n' >&2; exit 1; }
command -v scp >/dev/null 2>&1 || { printf 'scp is required.\n' >&2; exit 1; }

remote_dir="/tmp/k8s-setup"
remote="${REMOTE_USER}@${HOST}"
ssh "$remote" "mkdir -p '$remote_dir/scripts'"
scp "$CONFIG_FILE" "$remote:$remote_dir/cluster.env"
scp "$SCRIPT_DIR"/*.sh "$remote:$remote_dir/scripts/"
ssh "$remote" "chmod 700 '$remote_dir/scripts/'*.sh '$remote_dir/cluster.env'"

case "$ACTION" in
  bootstrap)
    if [[ "$ROLE" == worker ]]; then
      [[ -n "${JOIN_COMMAND:-}" ]] || { printf 'Set JOIN_COMMAND for a worker bootstrap.\n' >&2; exit 1; }
      join_command="$(printf '%q' "$JOIN_COMMAND")"
      ssh "$remote" "sudo env JOIN_COMMAND=$join_command CONFIG_FILE='$remote_dir/cluster.env' bash '$remote_dir/scripts/bootstrap.sh' worker"
    else
      ssh "$remote" "sudo CONFIG_FILE='$remote_dir/cluster.env' bash '$remote_dir/scripts/bootstrap.sh' control-plane"
    fi
    ;;
  upgrade)
    if [[ "$ROLE" == worker ]]; then
      [[ -n "${ADMIN_KUBECONFIG:-}" && -f "$ADMIN_KUBECONFIG" ]] || {
        printf 'Set ADMIN_KUBECONFIG to a local admin kubeconfig for worker draining.\n' >&2
        exit 1
      }
      scp "$ADMIN_KUBECONFIG" "$remote:$remote_dir/admin.conf"
      ssh "$remote" "chmod 600 '$remote_dir/admin.conf'; sudo KUBECONFIG='$remote_dir/admin.conf' CONFIG_FILE='$remote_dir/cluster.env' bash '$remote_dir/scripts/upgrade.sh' worker; rm -f '$remote_dir/admin.conf'"
    else
      ssh "$remote" "sudo CONFIG_FILE='$remote_dir/cluster.env' bash '$remote_dir/scripts/upgrade.sh' control-plane"
    fi
    ;;
  health)
    ssh "$remote" "sudo CONFIG_FILE='$remote_dir/cluster.env' bash '$remote_dir/scripts/health-check.sh'"
    ;;
esac