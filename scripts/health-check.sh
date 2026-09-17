#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

parse_dry_run "$@"
if [[ "$DRY_RUN" == true ]]; then
	log 'DRY RUN: would check every node for Ready status, list all pods, and query the Kubernetes API readyz endpoint.'
	exit 0
fi

require_root
require_command kubectl
[[ -f /etc/kubernetes/admin.conf ]] || die 'This node does not have admin kubeconfig.'
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl wait --for=condition=Ready nodes --all --timeout=5m
kubectl get nodes -o wide
kubectl get pods --all-namespaces
kubectl get --raw='/readyz?verbose'