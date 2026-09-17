#!/usr/bin/env bash
set -Eeuo pipefail

DRY_RUN=false
for argument in "$@"; do
  [[ "$argument" == --dry-run ]] && DRY_RUN=true
done

if [[ "$DRY_RUN" == true ]]; then
  printf 'DRY RUN: would install Helm 3 on this Ubuntu node using snapd.\n'
  exit 0
fi

if command -v helm >/dev/null 2>&1; then
  helm version --short
  exit 0
fi

SUDO=()
[[ "$EUID" -eq 0 ]] || SUDO=(sudo)
if ! command -v snap >/dev/null 2>&1; then
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y snapd
fi
"${SUDO[@]}" snap install helm --classic
helm version --short