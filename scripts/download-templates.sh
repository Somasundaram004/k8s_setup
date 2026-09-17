#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

parse_dry_run "$@"
require_config CNI_MANIFEST_FILE CNI_MANIFEST_URL
manifest_file="$CNI_MANIFEST_FILE"
[[ "$manifest_file" = /* ]] || manifest_file="$ROOT_DIR/$manifest_file"

if [[ "$DRY_RUN" == true ]]; then
  log "DRY RUN: would download the pinned CNI manifest from ${CNI_MANIFEST_URL}"
  log "Would store it locally at ${manifest_file} for review and cluster bootstrap."
  exit 0
fi

require_command curl
mkdir -p "$(dirname "$manifest_file")"
temporary_file="$(mktemp)"
trap 'rm -f "$temporary_file"' EXIT
curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 "$CNI_MANIFEST_URL" -o "$temporary_file"
[[ -s "$temporary_file" ]] || die 'Downloaded CNI manifest is empty.'
if [[ -n "${CNI_MANIFEST_SHA256:-}" ]]; then
  printf '%s  %s\n' "$CNI_MANIFEST_SHA256" "$temporary_file" | sha256sum --check --status || die 'CNI manifest checksum verification failed.'
fi
mv "$temporary_file" "$manifest_file"
chmod 0644 "$manifest_file"
log "Stored CNI manifest locally at ${manifest_file}"