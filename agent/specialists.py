from __future__ import annotations

from dataclasses import dataclass

from .llm import LLMClient


@dataclass(frozen=True)
class Specialist:
    name: str
    focus: str

    def run(self, goal: str, context: str, memory: str, client: LLMClient) -> str:
        system = (
            f"You are the {self.name} specialist. Focus on {self.focus}. "
            "Return concise findings, risks, and reversible next actions. "
            "Never claim to have executed commands or changed infrastructure."
        )
        prompt = f"Goal:\n{goal}\n\nRepository context:\n{context}\n\nPrior memory:\n{memory}"
        answer = client.complete(system, prompt)
        if answer:
            return answer
        return (
            f"{self.name}: inspect the requested change, validate it with --dry-run, "
            "then execute one reversible step at a time. Record the result for review."
        )


SPECIALISTS = (
    Specialist("Kubernetes specialist", "cluster lifecycle, upgrades, workloads, and zero-downtime safety"),
    Specialist("CI/CD specialist", "Docker images, registries, GitHub Actions, Helm, and Argo CD"),
    Specialist("Reliability specialist", "metrics, alerting, backups, security, and operational runbooks"),
)