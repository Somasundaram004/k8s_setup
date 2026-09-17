#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

parse_dry_run "$@"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-}"
MONITORING_CHART_VERSION="${MONITORING_CHART_VERSION:-}"
METRICS_SERVER_CHART_VERSION="${METRICS_SERVER_CHART_VERSION:-}"
ARGOCD_VALUES="$ROOT_DIR/templates/argocd-values.yaml"
MONITORING_VALUES="$ROOT_DIR/templates/kube-prometheus-stack-values.yaml"
METRICS_SERVER_VALUES="$ROOT_DIR/templates/metrics-server-values.yaml"

[[ -f "$ARGOCD_VALUES" ]] || die "Missing local Argo CD values: $ARGOCD_VALUES"
[[ -f "$MONITORING_VALUES" ]] || die "Missing local monitoring values: $MONITORING_VALUES"
[[ -f "$METRICS_SERVER_VALUES" ]] || die "Missing local metrics-server values: $METRICS_SERVER_VALUES"

if [[ "$DRY_RUN" == true ]]; then
  log "DRY RUN: would install or upgrade Argo CD in namespace ${ARGOCD_NAMESPACE}."
  log "Would use local values ${ARGOCD_VALUES} with ${ARGOCD_CHART_VERSION:-the configured chart version}."
  log "Would install or upgrade Prometheus, Alertmanager, Grafana, kube-state-metrics, and node-exporter in namespace ${MONITORING_NAMESPACE}."
  log "Would use local values ${MONITORING_VALUES} with ${MONITORING_CHART_VERSION:-the configured chart version}."
  log "Would install or upgrade Metrics Server in kube-system using ${METRICS_SERVER_VALUES}."
  log 'Services remain ClusterIP; access is through kubectl port-forward or a separately configured ingress/load balancer.'
  exit 0
fi

require_command helm
require_command kubectl
kubectl cluster-info >/dev/null

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
helm repo update

argocd_args=(upgrade --install argocd argo/argo-cd --namespace "$ARGOCD_NAMESPACE" --create-namespace --values "$ARGOCD_VALUES" --wait --timeout 15m)
monitoring_args=(upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace "$MONITORING_NAMESPACE" --create-namespace --values "$MONITORING_VALUES" --wait --timeout 15m)
metrics_server_args=(upgrade --install metrics-server metrics-server/metrics-server --namespace kube-system --values "$METRICS_SERVER_VALUES" --wait --timeout 10m)
if [[ -n "$ARGOCD_CHART_VERSION" ]]; then
  argocd_args+=(--version "$ARGOCD_CHART_VERSION")
fi
if [[ -n "$MONITORING_CHART_VERSION" ]]; then
  monitoring_args+=(--version "$MONITORING_CHART_VERSION")
fi
if [[ -n "$METRICS_SERVER_CHART_VERSION" ]]; then
  metrics_server_args+=(--version "$METRICS_SERVER_CHART_VERSION")
fi

helm "${argocd_args[@]}"
helm "${monitoring_args[@]}"
helm "${metrics_server_args[@]}"
kubectl -n "$ARGOCD_NAMESPACE" rollout status deployment/argocd-server --timeout=10m
kubectl -n "$MONITORING_NAMESPACE" rollout status deployment/kube-prometheus-stack-grafana --timeout=10m
kubectl -n kube-system rollout status deployment/metrics-server --timeout=10m
log 'Platform kit installed. Use kubectl get pods -n argocd, kubectl get pods -n monitoring, and kubectl top nodes to verify all components.'