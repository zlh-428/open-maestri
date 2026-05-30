# exec-plans

This directory is reserved for plan files that describe work the repository expects agents or humans to carry through over more than one round.

## Convention

- Put active plans under `docs/exec-plans/active/`
- Move finished plans to `docs/exec-plans/completed/`
- Keep one plan per coherent slice of work
- Link stable background material from `docs/reference/` instead of copying large context into each plan — `docs/reference/maestri-reference-index.md` is the canonical source for canvas, node, connection, and Maestro mode UI/interaction specs

## Naming Convention

Files should follow the pattern:

```
YYYY-MM-DD-topic-name.md
```

Examples:

```
2026-05-30-canvas-drag-refactor.md
2026-06-01-ipc-command-routing.md
2026-06-15-floors-worktree-integration.md
```

## Minimum Structure

Each plan should capture the following sections:

### Problem Statement

What is broken, missing, or needs improvement. Be specific about the current behavior and why it is insufficient.

### Intended End State

A clear description of what the system should look like once the work is complete. Prefer observable outcomes over implementation details.

### Verification Path

How to confirm the work is done. This should include build commands (`swift build`, `swift test`), manual steps in the app, or specific test filters such as:

```bash
swift test --filter OpenMaestriTests.<TestSuite>/<testMethod>
```

### Open Risks or Blockers

Known unknowns, dependencies on other plans, or areas where the approach may need to change. Update this section as the plan progresses rather than leaving it stale.
