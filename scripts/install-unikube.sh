#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

parse_dry_run "$@"
version="${UNIKUBE_VERSION:-latest}"
version_spec='unikube'
if [[ "$version" != latest ]]; then
  version_spec="unikube==${version}"
fi
if [[ "$DRY_RUN" == true ]]; then
  log "DRY RUN: would install ${version_spec} from PyPI using python3 and pip."
  exit 0
fi

require_root
apt-get update
apt-get install -y python3-pip
log "Installing ${version_spec} from PyPI"
if python3 -m pip help install | grep -q -- '--break-system-packages'; then
  python3 -m pip install --upgrade --break-system-packages "$version_spec"
else
  python3 -m pip install --upgrade "$version_spec"
fi
log 'UniKube installation finished; verify it with: command -v unikube && unikube version'