# open-maestri — Product Definition

> Canvas-based multi-agent orchestration layer for macOS. Not an AI agent — the workspace that surrounds and coordinates them.

---

## Problem

Developers running multiple AI coding agents simultaneously (Claude Code, Codex CLI, Gemini CLI, etc.) are forced to act as human routers — manually copying context between terminal windows, switching focus constantly, and losing the spatial relationship between ongoing tasks. There is no native macOS tool that treats multiple agents as a coordinated team rather than isolated processes.

---

## Target User

macOS developers who:

- Run 2+ AI coding agents concurrently on a single machine
- Work on multi-agent workflows (orchestrator + workers, reviewer + builder, etc.)
- Want local-first, open-source tooling without cloud dependencies or subscription gates
- Are comfortable building from source or using early-stage software

**Not for:** Users who only run a single AI agent, or who need a hosted/cloud solution.

---

## Product Principles

| Principle | What it means |
|-----------|--------------|
| **Orchestration layer, not an agent** | open-maestri provides the canvas; agents supply the intelligence |
| **Local-first** | All data stored in `~/.open-maestri/`; no cloud sync, no telemetry |
| **Native macOS** | Built with SwiftUI + AppKit; targets macOS 14.0+ (Sonoma) |
| **Open source** | Apache 2.0; skill ecosystem is open and extensible |
| **Maestri-compatible** | Full read/write compatibility with Maestri v0.25.4 workspace format |

---

## Feature Status

| Feature | Status | Notes |
|---------|--------|-------|
| Workspace management + infinite canvas | Implemented | Pan/zoom, minimap, physics-based rope connections |
| Terminal nodes (PTY) | Implemented | Full VT100/xterm-256color via SwiftTerm; scrollback persisted |
| Note nodes (Markdown) | Implemented | Raw + formatted dual-view; image paste; note chains |
| Connection + SkillInjector | Implemented | Auto-injects `omaestri` CLI into connected terminals |
| `omaestri` CLI (inter-agent communication) | Implemented | `ask`, `check`, `note read/write`, `list` |
| Maestro orchestration mode | Implemented | `recruit`, `dismiss`, `connect` commands |
| Portal (WKWebView browser node) | Implemented | `navigate`, `snapshot`, `click`, `fill` commands |
| File Tree + Git operations | Partial | File browsing works; Git operations incomplete |
| Floors (git worktree isolation) | Partial | Architecture in place; UX incomplete |
| Routines (scheduled tasks) | Partial | Scheduler exists; management UI incomplete |
| Remote SSH | Partial | Tunnel support scaffolded; not production-ready |
| Ombro (Apple Foundation Models) | Not implementing | Requires macOS 26+; out of scope |

---

## Success Criteria

**v1.0 (Baseline)**

- A developer can place 3+ agent terminals on a canvas, connect them, and have agents exchange messages via `omaestri ask` without manual copy-paste
- Canvas state (positions, sizes, connections) survives app restart with zero data loss
- Cold launch completes in under 1.5 seconds on M-series Mac
- Existing Maestri workspaces (`schemaVersion: 2`) open without errors

**Longer term**

- Maestro mode enables one agent to autonomously recruit, assign work to, and dismiss other agents through a full coding task
- File Tree git operations cover the common workflow (status, diff, commit, push)
- Portal automation commands sufficient for agents to drive a local web app for E2E verification

---

## Out of Scope

- **Ombro / on-device AI inference** — requires Apple Foundation Models (macOS 26+); deferred indefinitely
- **iOS / iPadOS** — macOS-only product; no `#available` iOS branches
- **Cloud sync or remote workspaces** — local-first; no backend infrastructure
- **Built-in LLM** — open-maestri is model-agnostic; it wraps whatever CLI the developer chooses

---

## Future Directions

- **Linux / Windows ports** — community-driven long-term goal; architecture is SPM-based to ease porting
- **Floors (full git worktree UX)** — each Floor maps to a branch; agents work in isolation without polluting each other's state
- **Routines (scheduled automation)** — cron-like task runner that can trigger agent workflows on a schedule
- **Remote SSH nodes** — treat remote machines as first-class canvas nodes
- **Skill marketplace** — open registry for community-contributed agent skill scripts
