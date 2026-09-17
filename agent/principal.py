from __future__ import annotations

from pathlib import Path

from .llm import LLMClient
from .memory import MemoryStore
from .specialists import SPECIALISTS


def repository_context(root: Path) -> str:
    files = sorted(
        str(path.relative_to(root))
        for path in root.rglob("*")
        if path.is_file() and ".git" not in path.parts and "memory" not in path.parts
    )
    return "\n".join(files[:150])


def run(root: Path, goal: str, memory_path: Path) -> dict[str, object]:
    memory_store = MemoryStore(memory_path)
    client = LLMClient()
    context = repository_context(root)
    previous = memory_store.recent()
    memory_text = "\n".join(str(item) for item in previous) or "No prior run memory."
    reports = {
        specialist.name: specialist.run(goal, context, memory_text, client)
        for specialist in SPECIALISTS
    }
    principal_prompt = (
        "As principal agent, synthesize these specialist reports into a prioritized "
        "execution plan. Include assumptions, validation commands, and explicit human "
        "approval points before any destructive or production action.\n\n"
        + "\n\n".join(f"{name}:\n{report}" for name, report in reports.items())
    )
    synthesis = client.complete(
        "You are the principal platform agent. Be conservative, auditable, and concise.",
        principal_prompt,
    ) or "Review the specialist reports, run the repository dry-run, and approve each production action explicitly."
    result: dict[str, object] = {
        "goal": goal,
        "model_enabled": client.enabled,
        "specialists": reports,
        "principal_plan": synthesis,
    }
    memory_store.append(result)
    return result