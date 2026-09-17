#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

parse_dry_run "$@"
IMAGE="${POSITIONAL_ARGS[0]:-}"
CONTEXT="${POSITIONAL_ARGS[1]:-.}"
[[ -n "$IMAGE" ]] || die 'Usage: build-image.sh [--dry-run] image:tag [context]'

if [[ "$DRY_RUN" == true ]]; then
  log "DRY RUN: would build Docker image ${IMAGE} from ${CONTEXT} and tag it locally."
  log 'Would use the Dockerfile in the context and would not push or modify a registry.'
  exit 0
fi

require_command docker
docker build --tag "$IMAGE" "$CONTEXT"
log "Built ${IMAGE}. Push it with: docker push ${IMAGE}"