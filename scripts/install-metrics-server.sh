#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"
parse_dry_run "$@"
VALUES="${METRICS_SERVER_VALUES:-$ROOT_DIR/templates/metrics-server-values.yaml}"
if [[ "$DRY_RUN" == true ]]; then
  log "DRY RUN: would install Metrics Server from ${VALUES} in kube-system."
  exit 0
fi
require_command helm
require_command kubectl
[[ -f "$VALUES" ]] || die "Missing Metrics Server values: $VALUES"
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
helm repo update
helm upgrade --install metrics-server metrics-server/metrics-server --namespace kube-system --values "$VALUES" --wait --timeout 10m
kubectl -n kube-system rollout status deployment/metrics-server --timeout=10m