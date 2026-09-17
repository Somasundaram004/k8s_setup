#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"
parse_dry_run "$@"
NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
VALUES="${ARGOCD_VALUES:-$ROOT_DIR/templates/argocd-values.yaml}"
if [[ "$DRY_RUN" == true ]]; then
  log "DRY RUN: would install or upgrade Argo CD in ${NAMESPACE} using ${VALUES}."
  exit 0
fi
require_command helm
require_command kubectl
[[ -f "$VALUES" ]] || die "Missing Argo CD values: $VALUES"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update
helm upgrade --install argocd argo/argo-cd --namespace "$NAMESPACE" --create-namespace --values "$VALUES" --wait --timeout 15m
kubectl -n "$NAMESPACE" rollout status deployment/argocd-server --timeout=10m