from __future__ import annotations

import argparse
import json
from pathlib import Path

from .principal import run


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the repository principal agent.")
    parser.add_argument("goal", nargs="?", default="Review Kubernetes platform health and pending safe improvements.")
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--memory", type=Path, default=None)
    args = parser.parse_args()
    memory = args.memory or args.root / "agent" / "memory" / "runs.jsonl"
    print(json.dumps(run(args.root.resolve(), args.goal, memory), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())