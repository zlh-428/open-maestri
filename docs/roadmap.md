# Roadmap

<a href="roadmap.zh-CN.md">中文</a> | <strong>English</strong>

open-maestri is community-driven. The core team maintains the canvas engine and agent communication protocol, but most of the interesting work happens at the edges — better node types, richer CLI commands, deeper git integration, and eventually cross-platform support. If something on this list matters to you, open an issue or send a PR.

## Focus Areas

| # | Area | Description | Status | Links |
|---|------|-------------|--------|-------|
| 1 | **Canvas Engine** | Infinite canvas rendering, pan/zoom, minimap, node drag and resize | Active | — |
| 2 | **Terminal Nodes (PTY)** | Full VT100/xterm-256color interactive terminals via SwiftTerm, agent presets, scrollback persistence | Active | — |
| 3 | **Note Nodes** | Markdown edit + live preview dual-view, image paste, note chains, import from Finder | Active | — |
| 4 | **Inter-Agent Communication** | `omaestri` CLI injected on connect — `ask`, `check`, `note read/write` | Active | — |
| 5 | **Portal (Embedded Browser)** | WKWebView canvas node with agent-driven automation: `navigate`, `snapshot`, `click`, `fill` | Active | — |
| 6 | **Connection & SkillInjector** | Physics-based rope connections, automatic skill script injection on terminal connect | Active | — |
| 7 | **File Tree & Git Operations** | File browser node with directory tree; git status, diff, and staging — partially implemented | In Progress | — |
| 8 | **Maestro Orchestration Mode** | One agent as team lead: `recruit`, `connect`, `dismiss` — core commands work, richer lifecycle management needed | In Progress | — |
| 9 | **Floors (Git Worktree Isolation)** | Each Floor maps to a git worktree branch, giving agents isolated working copies on the same canvas | Planned | — |
| 10 | **Routines (Scheduled Tasks)** | Define recurring automations triggered by time or canvas events | Planned | — |
| 11 | **Remote SSH** | SSH tunnel support so agent nodes can target remote machines | Planned | — |
| 12 | **omaestri CLI Completeness** | Audit and close gaps between `omaestri` and the full Maestri CLI surface | Open | — |
| 13 | **Agent Role System** | Richer role definitions and capability scoping for Maestro-spawned agents | Open | — |
| 14 | **macOS Spotlight Integration** | Index workspace content via CoreSpotlight for quick search | Open | — |
| 15 | **Architecture & Code Quality** | Reduce coupling between canvas, terminal, and persistence layers; improve test coverage | Open | — |
| 16 | **Linux / Windows Port** | Long-term: bring the canvas to non-Apple platforms | Open | — |

**Status legend**: `Active` = core team focus · `In Progress` = work started · `Planned` = accepted, not started · `Open` = community-driven, open an issue first

---

## What Is Not on the Roadmap

**Ombro** (the on-device AI companion in Maestri that requires Apple Foundation Models and macOS 26+) is explicitly out of scope. open-maestri targets macOS 14.0+ (Sonoma) and will not depend on APIs unavailable on that baseline.

---

## Contributing

The items marked `Open` above are the best entry points for new contributors. Before starting significant work:

1. Check [open issues](https://github.com/your-org/open-maestri/issues) to avoid duplication.
2. Open an issue describing what you plan to build and why.
3. The core team will respond with feedback or a green light.

For smaller fixes and improvements, a PR with a clear description is always welcome — no issue required.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for development setup, coding conventions, and the PR process.
