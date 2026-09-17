#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/.repo-export}"
OWNER="${1:-}"
PRIVATE="${PRIVATE_REPOS:-true}"

command -v gh >/dev/null 2>&1 || { printf 'GitHub CLI is required. Install it and run gh auth login.\n' >&2; exit 1; }
[[ -n "$OWNER" ]] || { printf 'Usage: %s OWNER\n' "$0" >&2; exit 1; }
gh auth status >/dev/null
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

copy_common() {
  local destination="$1"
  mkdir -p "$destination"
  cp "$ROOT_DIR/README.md" "$ROOT_DIR/.gitignore" "$destination/"
}

create_repo() {
  local name="$1"
  local destination="$2"
  local visibility='--private'
  [[ "$PRIVATE" == false ]] && visibility='--public'
  gh repo create "$OWNER/$name" "$visibility" --source "$destination" --remote origin --push
}

infra="$OUTPUT_DIR/k8s-infra"
copy_common "$infra"
mkdir -p "$infra/scripts" "$infra/templates"
cp "$ROOT_DIR/scripts/common.sh" "$ROOT_DIR/scripts/bootstrap.sh" "$ROOT_DIR/scripts/upgrade.sh" \
  "$ROOT_DIR/scripts/install-helm.sh" "$ROOT_DIR/scripts/download-templates.sh" "$infra/scripts/"
cp "$ROOT_DIR/templates/calico.yaml" "$infra/templates/"
(cd "$infra" && git init -q && git add . && git commit -qm 'feat: TEST01 add infrastructure repository')

platform="$OUTPUT_DIR/k8s-platform"
copy_common "$platform"
mkdir -p "$platform/scripts" "$platform/templates"
cp "$ROOT_DIR/scripts/install-platform-kit.sh" "$platform/scripts/"
cp "$ROOT_DIR/templates/argocd-values.yaml" "$ROOT_DIR/templates/kube-prometheus-stack-values.yaml" \
  "$ROOT_DIR/templates/metrics-server-values.yaml" "$platform/templates/"
(cd "$platform" && git init -q && git add . && git commit -qm 'feat: TEST01 add platform services repository')

application="$OUTPUT_DIR/nginx-app"
copy_common "$application"
mkdir -p "$application/scripts" "$application/templates/apps" "$application/templates/ci"
cp "$ROOT_DIR/scripts/deploy-nginx.sh" "$ROOT_DIR/scripts/build-image.sh" "$application/scripts/"
cp -R "$ROOT_DIR/templates/apps/nginx" "$application/templates/apps/"
cp -R "$ROOT_DIR/templates/ci/." "$application/templates/ci/"
(cd "$application" && git init -q && git add . && git commit -qm 'feat: TEST01 add highly available nginx application')

create_repo "${INFRA_REPO_NAME:-k8s-infra}" "$infra"
create_repo "${PLATFORM_REPO_NAME:-k8s-platform}" "$platform"
create_repo "${APP_REPO_NAME:-nginx-app}" "$application"
printf 'Created and pushed repositories under %s. Local export: %s\n' "$OWNER" "$OUTPUT_DIR"