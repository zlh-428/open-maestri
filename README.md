# open-maestri

> Open-source multi-agent orchestration canvas for macOS — manage AI agents like a team, not a terminal.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-5.9-orange.svg)](https://swift.org)
[![CI](https://github.com/your-org/open-maestri/actions/workflows/ci.yml/badge.svg)](https://github.com/your-org/open-maestri/actions)

[中文文档](README-zh.md)

---

## What is open-maestri?

open-maestri is a **canvas-based orchestration layer** for the Agentic AI era. It is not an AI agent itself — it is the workspace that surrounds and coordinates them.

Place terminals, AI agents, Markdown notes, file browsers, and embedded browsers together on an infinite spatial canvas. Connect them with physics-based rope animations. Let agents communicate directly through the `omaestri` CLI without you acting as a human router.

**Core pain point:** When running multiple AI coding agents (Claude Code, Codex CLI, Gemini CLI, etc.) simultaneously, developers are forced to manually shuttle context between terminal windows. open-maestri eliminates that friction.

---

## Key Features

### Infinite Canvas
- Drag and drop Terminal, Note, File Tree, Portal, and Text nodes onto an infinite canvas
- Pan and zoom with trackpad gestures or mouse scroll
- Physics-based rope animations for connections (catenary curve, 21 control points)
- Minimap for quick navigation

### Terminal & Agent Nodes
- Full VT100/xterm-256color interactive PTY via [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
- Built-in agent presets: Claude Code, Codex CLI, Gemini CLI, OpenCode, Shell
- Agent status indicator (running / idle)
- Scrollback history persisted across restarts

### Inter-Agent Communication
Agents communicate via the `omaestri` CLI, automatically injected when terminals are connected:

```bash
omaestri list                          # List connected agents, notes, portals
omaestri ask "Reviewer" "Review my PR" # Send message and wait for response
omaestri check "Builder"               # Read target agent's current output
omaestri note read "Spec"              # Read a connected Note
omaestri note write "Spec" "content"   # Write to a Note
```

### Maestro Mode
One agent acts as the team lead — recruiting, connecting, and dismissing agents programmatically:

```bash
omaestri recruit "Builder" --preset claude-code --role coder
omaestri connect "Builder" "Spec"
omaestri dismiss "Builder"
```

### Note Nodes
- Raw (Markdown edit) and Formatted (live preview) dual-view
- Paste images directly into notes
- Note chains: connect notes to notes, agents traverse the entire chain
- Import `.md` / `.txt` files by dragging from Finder

### Portal (Embedded Browser)
- WKWebView in a canvas node
- Agent-controlled browser automation via `omaestri portal` commands:
  ```bash
  omaestri portal navigate "Browser" "http://localhost:3000"
  omaestri portal snapshot "Browser"   # accessibility tree
  omaestri portal click "Browser" @e3
  omaestri portal fill "Browser" @e1 "admin"
  ```

### Workspace Persistence
- Full canvas layout (positions, sizes, connections) restored on restart
- Auto-save every 30 seconds (background thread, no UI blocking)
- Crash recovery via `cleanShutdown` flag
- Compatible with **Maestri v0.25.4** `workspace.json` format

---

## Why open-maestri?

| | open-maestri | Maestri |
|---|---|---|
| License | Apache 2.0 (free forever) | Proprietary (SetApp) |
| macOS requirement | **14.0+ (Sonoma)** | macOS 26.2+ |
| Source available | Yes | No |
| Data format | Fully compatible | Maestri native |
| CLI compatible | Yes (`omaestri` = `maestri`) | Yes |
| Skill ecosystem | Open, extensible | Closed |

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16+ (for building from source)
- Swift 5.9+

---

## Installation

### Download (Recommended)

Download the latest signed `.dmg` from [GitHub Releases](https://github.com/your-org/open-maestri/releases).

### Build from Source

```bash
git clone https://github.com/your-org/open-maestri.git
cd open-maestri

# Build with Swift Package Manager
swift build -c release

# Or open in Xcode
open Package.swift
```

### Build with Xcode (CI-compatible)

```bash
xcodebuild \
  -scheme open-maestri \
  -destination 'platform=macOS' \
  build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO
```

---

## Project Structure

```
open-maestri/
├── Sources/                    # Swift source code
│   ├── App/                    # App lifecycle, window management
│   ├── Canvas/                 # Infinite canvas rendering (NSView)
│   ├── Connection/             # Rope physics and connection logic
│   ├── Terminal/               # PTY terminal nodes (SwiftTerm)
│   ├── Note/                   # Markdown note nodes
│   ├── InterAgent/             # omaestri CLI HTTP server
│   ├── Workspace/              # Persistence, serialization
│   ├── Settings/               # Preferences UI
│   ├── Portal/                 # WKWebView browser nodes
│   ├── FileTree/               # File browser nodes
│   ├── Floor/                  # Git worktree branch isolation
│   ├── Routine/                # Scheduled task automation
│   ├── SSH/                    # Remote SSH tunnel support
│   ├── Maestro/                # Maestro orchestration mode
│   ├── Roles/                  # Agent role system
│   ├── Spotlight/              # macOS CoreSpotlight integration
│   ├── Shared/                 # Shared utilities and models
│   └── OpenMaestriApp.swift    # App entry point
├── Tests/
│   └── OpenMaestriTests/       # Unit and integration tests
├── Package.swift               # Swift Package Manager manifest
├── .github/workflows/ci.yml    # GitHub Actions CI
└── LICENSE                     # Apache 2.0
```

---

## omaestri CLI Reference

The `omaestri` script is automatically injected into connected terminals. It communicates with the app via a local HTTP server (`127.0.0.1` only).

| Command | Description |
|---------|-------------|
| `omaestri list` | List connected agents, notes, portals |
| `omaestri ask "Name" "prompt"` | Send message, wait for response |
| `omaestri check "Name"` | Read target agent's terminal output |
| `omaestri note create "Name"` | Create a new note |
| `omaestri note read "Name" [--offset N] [--limit N]` | Read note content |
| `omaestri note write "Name" "content"` | Write to note |
| `omaestri recruit "Name" [--preset P] [--role R]` | Spawn new agent (Maestro only) |
| `omaestri dismiss "Name"` | Close and remove agent (Maestro only) |
| `omaestri connect "From" "To"` | Connect two nodes (Maestro only) |
| `omaestri portal navigate "Name" "url"` | Navigate portal to URL |
| `omaestri portal snapshot "Name"` | Get accessibility tree |
| `omaestri portal click "Name" @ref` | Click element |
| `omaestri portal fill "Name" @ref "value"` | Fill input field |

---

## Compatibility

open-maestri maintains full compatibility with Maestri v0.25.4:

- **workspace.json** (`schemaVersion: 2`): read and write compatible
- **omaestri CLI**: identical command interface to `maestri` CLI
- **Agent Skills**: existing Maestri Skill scripts work without modification

---

## Contributing

Contributions are welcome. Please read the [contributing guidelines](CONTRIBUTING.md) before submitting a PR.

```bash
# Run tests
swift test

# Or with xcodebuild
xcodebuild \
  -scheme open-maestri \
  -destination 'platform=macOS' \
  test \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO
```

**Areas actively seeking contributors:**

- Portal browser automation commands
- File Tree git operations
- Floors (git worktree integration)
- Routines (scheduled task scheduler)
- Remote SSH support
- Linux / Windows ports (long term)

---

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.

---

## Acknowledgments

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — terminal emulation
- [Sparkle](https://github.com/sparkle-project/Sparkle) — auto-update framework
- [Maestri](https://maestriapp.com) — the original product that inspired this open-source reimplementation
