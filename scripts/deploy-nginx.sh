#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

parse_dry_run "$@"
IMAGE="nginx:1.27-alpine"
for argument in "${POSITIONAL_ARGS[@]}"; do
  if [[ "$argument" == image=* ]]; then
    IMAGE="${argument#image=}"
  else
    die "Unknown option: $argument"
  fi
done
MANIFEST_DIR="$ROOT_DIR/templates/apps/nginx"
if [[ "$DRY_RUN" == true ]]; then
  log "DRY RUN: would apply the HA Nginx application manifests from ${MANIFEST_DIR}."
  log "Would deploy image ${IMAGE} with 3 replicas, maxUnavailable=0, readiness/liveness probes, topology spreading, and a 2-pod disruption budget."
  exit 0
fi

require_command kubectl
[[ -d "$MANIFEST_DIR" ]] || die "Missing Nginx templates: $MANIFEST_DIR"
kubectl apply -k "$MANIFEST_DIR"
kubectl -n nginx-app set image deployment/nginx "nginx=${IMAGE}"
kubectl -n nginx-app rollout status deployment/nginx --timeout=10m
kubectl -n nginx-app wait --for=condition=Available deployment/nginx --timeout=10m
kubectl -n nginx-app get deployment,service,pdb,pods -o wide