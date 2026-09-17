#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOAL="${*:-Review Kubernetes platform health and pending safe improvements.}"
exec python3 -m agent.cli --root "$ROOT_DIR" "$GOAL"