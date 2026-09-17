# Contribution Rules

Every feature or operational change must update both:

1. `README.md` with user-facing setup, behavior, and operational instructions.
2. `docs/architecture.md` with the current end-to-end architecture and affected control/data flows.

Use the detailed commit format:

```text
feat: TEST01 <detailed subject>

Detailed body describing the implementation, validation, security impact, and operational impact.
```

Run the narrowest available validation before committing. Do not document a component as deployed unless the deployment was actually verified.