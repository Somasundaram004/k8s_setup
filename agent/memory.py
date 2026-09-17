from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class MemoryStore:
    """Small append-only memory store; entries are reviewable in Git."""

    def __init__(self, path: Path, max_entries: int = 100):
        self.path = path
        self.max_entries = max_entries

    def recent(self, limit: int = 10) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        entries: list[dict[str, Any]] = []
        for line in self.path.read_text(encoding="utf-8").splitlines():
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict):
                entries.append(value)
        return entries[-limit:]

    def append(self, entry: dict[str, Any]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        entries = self.recent(self.max_entries - 1)
        entries.append({
            "recorded_at": datetime.now(timezone.utc).isoformat(),
            **entry,
        })
        self.path.write_text(
            "".join(json.dumps(item, sort_keys=True) + "\n" for item in entries),
            encoding="utf-8",
        )