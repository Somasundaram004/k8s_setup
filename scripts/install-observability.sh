#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"
parse_dry_run "$@"
NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
VALUES="${MONITORING_VALUES:-$ROOT_DIR/templates/kube-prometheus-stack-values.yaml}"
if [[ "$DRY_RUN" == true ]]; then
  log "DRY RUN: would install Prometheus, Alertmanager, Grafana, kube-state-metrics, and node-exporter in ${NAMESPACE}."
  exit 0
fi
require_command helm
require_command kubectl
[[ -f "$VALUES" ]] || die "Missing monitoring values: $VALUES"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace "$NAMESPACE" --create-namespace --values "$VALUES" --wait --timeout 15m
kubectl -n "$NAMESPACE" rollout status deployment/kube-prometheus-stack-grafana --timeout=10m