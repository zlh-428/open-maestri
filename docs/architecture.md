# Architecture

open-maestri is a macOS infinite-canvas application that hosts AI agent terminals and connects them for inter-agent communication. It is a feature-compatible open-source implementation of Maestri v0.25.4, sharing the same on-disk format.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 5.9 |
| UI framework | SwiftUI (views) + AppKit NSView (canvas engine) |
| State management | `@Observable` (macOS 14+, no `ObservableObject`) |
| Terminal emulator | SwiftTerm (PTY wrapper) |
| Web view | WKWebView |
| IPC transport | Unix socket + HTTP/1.x (`POST /cli`) |
| Concurrency | Swift Structured Concurrency + `@MainActor` |
| Persistence | JSON, atomic writes via `PersistenceManager` |
| Minimum deployment | macOS 14.0 |

## System Shape

| Module | Path | Responsibility |
|--------|------|----------------|
| App state | `Sources/App/AppState.swift` | `@Observable` root; cold-launch < 1.5 s, autosave every 30 s |
| Canvas engine | `Sources/Canvas/` | `CanvasViewportView` (NSView); infinite canvas, origin ≈ (9800, 8500) |
| Node layer | `Sources/Canvas/NodeLayer/` | Per-type SwiftUI views rendered by `CanvasNodeRenderer` |
| Connection layer | `Sources/Canvas/ConnectionLayer/` | Rope-physics overlay, `RopePathRenderer` |
| Workspace | `Sources/Workspace/` | `WorkspaceManager` + `PersistenceManager` (singleton, atomic I/O) |
| Node model | `Sources/Workspace/Models/` | `CanvasNode` + `NodeContent` enum (6 content types) |
| Terminal | `Sources/Terminal/` | `SwiftTermProvider` PTY lifecycle, `TerminalManager` singleton |
| Connection mgr | `Sources/Connection/ConnectionManager.swift` | `@MainActor` singleton; tracks active connections, triggers `SkillInjector` |
| Skill injection | `Sources/Connection/SkillInjector.swift` | Injects `omaestri` CLI script into PTY on connect |
| IPC server | `Sources/InterAgent/InterAgentServer.swift` | Unix socket + TCP listener; single route `POST /cli` |
| CLI router | `Sources/InterAgent/CLIRouter.swift` | Dispatches args to handlers; semaphore-bridges async→sync |
| CLI handlers | `Sources/InterAgent/Handlers/` | `AskHandler`, `CheckHandler`, `ListHandler`, `MaestroHandlers`, `NoteHandler`, `PortalHandler` |
| Portal | `Sources/Portal/` | WKWebView nodes, isolated/shared storage scope |
| File tree | `Sources/FileTree/` | Directory watcher, NSOutlineView adapter |
| Note | `Sources/Note/` | Markdown editor + renderer, `NoteFileManager` |

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  AppState (@Observable)                                          │
│    activeWorkspaceId  workspaces[]  preferences  manifest        │
│         │                                                        │
│         ▼                                                        │
│  WorkspaceManager (one per workspace)                            │
│    isDirty flag ──► autosave (background, every 30s)            │
│         │                                                        │
│         ▼                                                        │
│  WorkspaceDocument (serialization root)                          │
│    ├─ [CanvasNode]          frame: [[x,y],[w,h]]                 │
│    ├─ [TerminalConnection]  rope physics control points          │
│    ├─ [NoteConnection]                                           │
│    ├─ [PortalConnection]                                         │
│    └─ CanvasState           origin + zoom (runtime only)         │
└─────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────┐
│  CanvasViewportView (NSView)        │
│  ┌──────────────────────────────┐  │
│  │  CanvasNodesView (SwiftUI)   │  │
│  │    NodeShellView             │  │
│  │      TerminalNodeSwiftUIView │  │
│  │      NoteNodeSwiftUIView     │  │
│  │      PortalNodeSwiftUIView   │  │
│  │      FileTreeNodeSwiftUIView │  │
│  │      TextNodeSwiftUIView     │  │
│  │      DrawingNodeSwiftUIView  │  │
│  └──────────────────────────────┘  │
│  ┌──────────────────────────────┐  │
│  │  ConnectionOverlayView       │  │
│  │    RopePathRenderer          │  │
│  └──────────────────────────────┘  │
└────────────────────────────────────┘
```

## IPC / Inter-Agent Protocol

Terminals communicate with the app through the `omaestri` CLI script, which is injected automatically when a terminal node connects to another node via `SkillInjector`.

```
Terminal PTY
    │
    │  omaestri ask "Agent-B" "prompt text"
    ▼
Unix socket  ──►  ~/.open-maestri/run/agent.sock
                        │  (single global socket, survives workspace switches)
                        ▼
               InterAgentServer
                  parseHTTPRequest()
                  extract X-Terminal-ID header
                        │
                        ▼
                  CLIRouter.route(args:terminalId:)
                  ┌────────────────────────────────────┐
                  │  list      → ListHandler            │
                  │  ask       → AskHandler             │
                  │  check     → CheckHandler           │
                  │  note      → NoteHandler            │
                  │  portal    → PortalHandler          │
                  │  recruit   → MaestroHandlers        │
                  │  dismiss   → MaestroHandlers        │
                  │  connect   → MaestroHandlers        │
                  │  role      → MaestroHandlers        │
                  │  preset    → MaestroHandlers        │
                  └────────────────────────────────────┘
                        │
                        ▼  plain text
                  HTTP response body printed to terminal
```

**Request format**
```json
POST /cli HTTP/1.0
X-Terminal-ID: <UUID>
Content-Type: application/json

{ "args": ["ask", "AgentName", "your prompt"] }
```

**Response**: `text/plain`, printed directly by the CLI.

## Node Content Model

`NodeContent` is a Swift enum with six variants. All variants use the `{ "type": { "_0": ... } }` wrapping format for Maestri compatibility.

| Variant | Struct | Notes |
|---------|--------|-------|
| `terminal` | `TerminalContent` | PTY agent; `agentType` ∈ `claude_code`, `codex`, `gemini_cli`, `open_code`, `generic_shell` |
| `stickyNote` | `StickyNoteContent` | Markdown file backed; `storageMode`: `managed` or `custom(path:)` |
| `portal` | `PortalContent` | WKWebView; `storageScope`: `isolated` or `shared` |
| `fileTree` | `FileTreeContent` | Directory watcher + NSOutlineView |
| `text` | `TextContent` | Lightweight canvas label, no header chrome |
| `drawing` | `DrawingContent` | Freehand strokes `[[x,y]]` with color + width |

**Frame format**: `CanvasNode.frame` is stored as `[[x, y], [w, h]]` (not `CGRect`). Use `CGRect+Frame.swift` extensions to convert.

## Connection Model

`ConnectionManager` (@MainActor singleton) maintains in-memory `ActiveConnection` records. Persisted connection types live in `WorkspaceDocument`.

| Connection type | Persisted struct | Visual status |
|-----------------|-----------------|---------------|
| Terminal ↔ Terminal | `TerminalConnection` | Idle (grey dashed) / Communicating (green glow) / Error (red dashed) |
| Terminal → Note | `NoteConnection` | Same state machine |
| Terminal → Portal | `PortalConnection` | Same state machine |
| Note ↔ Note | `NoteToNoteConnection` | Chaining only |
| Portal ↔ Portal | `PortalToPortalConnection` | Shared session |

On connection, `SkillInjector` injects the `omaestri` script into both terminal PTYs. On workspace restore, `restoreConnections(from:serverPort:)` re-injects without regenerating UUIDs, keeping CLI query results stable.

## State Management

```
@MainActor (all canvas mutations)
    AppState
        └─ WorkspaceManager.isDirty  ──►  autosave (background Task)
                                          PersistenceManager.shared (atomic writes)

Non-UI work (background Tasks / Task.detached):
    - PersistenceManager file I/O
    - InterAgentServer request handling
    - CLIRouter.routeAsync (semaphore bridge back to @MainActor when needed)
```

Crash recovery: on cold launch, `app-state.json` is checked for `cleanShutdown: false`. If found, `AppState.needsRecovery` is set and the UI can prompt the user. The flag is reset to `false` at launch and written `true` only on clean app termination.

## On-Disk Layout

```
~/.open-maestri/
├── manifest.json               schemaVersion: 1, workspace index
├── preferences.json
├── app-state.json              activeWorkspaceId, cleanShutdown flag
├── run/
│   └── agent.sock              global Unix socket (recreated each launch)
└── workspaces/{UUID}/
    ├── workspace.json          schemaVersion: 2 (Maestri v0.25.4 compatible)
    ├── notes/{name}.md         note content files
    └── terminals/{UUID}.scrollback
```

## Engineering Rules

- **No iOS code.** `#available` is used only for macOS version branches.
- **All `@State` properties must be `private`.**
- **Canvas mutations must be on `@MainActor`.** Off-thread canvas writes are a compile error.
- **All file I/O goes through `PersistenceManager.shared`.** Direct `FileManager` use is forbidden outside that class.
- **New CLI commands**: register in `CLIRouter.swift`, create a `Handler` file in `Sources/InterAgent/Handlers/`.
- **New node types**: follow the `{ "type": { "_0": ... } }` wrapping in `NodeContent`; add a renderer in `Sources/Canvas/NodeLayer/`.
- **Autosave is dirty-flag-gated.** Only workspaces with `isDirty == true` are serialized each cycle.
- **Cold launch target**: < 1.5 s. The three root JSON files (`app-state`, `preferences`, `manifest`) are read concurrently via `async let`.
