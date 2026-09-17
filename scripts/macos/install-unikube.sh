#!/usr/bin/env bash
set -Eeuo pipefail

DRY_RUN=false
for argument in "$@"; do
  [[ "$argument" == --dry-run ]] && DRY_RUN=true
done
version="${UNIKUBE_VERSION:-latest}"
if [[ "$DRY_RUN" == true ]]; then
  if [[ "$version" == latest ]]; then
    printf 'DRY RUN: would install the latest unikube package with Homebrew Python and pipx.\n'
  else
    printf 'DRY RUN: would install unikube==%s with Homebrew Python and pipx.\n' "$version"
  fi
  exit 0
fi

command -v brew >/dev/null 2>&1 || {
  printf 'Homebrew is required: https://brew.sh\n' >&2
  exit 1
}

brew install python pipx
pipx ensurepath
if [[ "$version" == latest ]]; then
  pipx install --force unikube
else
  pipx install --force "unikube==${version}"
fi

printf 'UniKube is installed for macOS. Open a new shell, then run: unikube version\n'