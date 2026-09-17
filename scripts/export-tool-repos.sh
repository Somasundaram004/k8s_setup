#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/.tool-repo-export}"
OWNER="${1:-}"
PRIVATE="${PRIVATE_REPOS:-true}"
command -v gh >/dev/null 2>&1 || { printf 'GitHub CLI is required. Run gh auth login first.\n' >&2; exit 1; }
[[ -n "$OWNER" ]] || { printf 'Usage: %s OWNER\n' "$0" >&2; exit 1; }
gh auth status >/dev/null
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

make_repo() {
  local repo_name="$1"
  local title="$2"
  local destination="$OUTPUT_DIR/$repo_name"
  shift 2
  mkdir -p "$destination"
  cp "$ROOT_DIR/.gitignore" "$destination/"
  printf '# %s\n\nThis focused repository is exported from k8s_setup and is independently deployable.\n' "$title" > "$destination/README.md"
  for source in "$@"; do
    mkdir -p "$destination/$(dirname "$source")"
    cp -R "$ROOT_DIR/$source" "$destination/$source"
  done
  (cd "$destination" && git init -q && git add . && git commit -qm "feat: TEST01 add ${title}" -m "Create the focused ${title} repository with its local templates and operational entry points.")
  local visibility='--private'
  [[ "$PRIVATE" == false ]] && visibility='--public'
  gh repo create "$OWNER/$repo_name" "$visibility" --source "$destination" --remote origin --push
}

make_repo k8s-argocd 'Argo CD deployment tool' scripts/common.sh scripts/install-argocd.sh templates/argocd-values.yaml
make_repo k8s-observability 'Prometheus Grafana and Alertmanager deployment tool' scripts/common.sh scripts/install-observability.sh templates/kube-prometheus-stack-values.yaml
make_repo k8s-metrics-server 'Kubernetes Metrics Server deployment tool' scripts/common.sh scripts/install-metrics-server.sh templates/metrics-server-values.yaml
make_repo k8s-unikube 'UniKube CLI installation tool' scripts/common.sh scripts/install-unikube.sh scripts/macos/install-unikube.sh
make_repo k8s-ai-agent 'Principal AI agent and specialist runner' agent scripts/run-agent.sh .github/workflows/agent-runner.yml
make_repo k8s-ci-cd 'Docker and GitHub Actions CI CD tool' scripts/build-image.sh templates/ci .github/workflows/self-service-nginx.yml
printf 'Created and pushed six focused tool repositories for %s.\n' "$OWNER"