# Contributing to open-maestri

<a href="CONTRIBUTING.zh-CN.md">中文</a> | <strong>English</strong>

---

## Human Parts

*This section is written for humans.*

open-maestri is an AI-native canvas built around the idea that AI agents should be first-class collaborators — not just tools. We believe the best contributions come from using the app the way it was meant to be used: with an agent by your side. Whether you are fixing a bug, proposing a feature, or refactoring code, letting an agent do the heavy lifting is not cheating. It is the point.

You do not need to know Swift to contribute. You need a clear description of what is wrong or what you want, and an agent that can turn that into a pull request.

### Getting Started

Clone the repo and paste this prompt into your code agent (Claude Code, Cursor, Copilot, etc.) to orient it:

```
I am contributing to open-maestri, an AI-native infinite canvas for macOS.
Please read CLAUDE.md for the full architecture overview, coding conventions,
and build commands. Then read CONTRIBUTING.md for contribution guidelines.
Let me know when you are ready and what questions you have.
```

Your agent will read `CLAUDE.md`, understand the project layout, and guide you through making your change.

---

### Report a Bug via Your Code Agent

Found something broken? Paste the following prompt into your agent, fill in the blanks, and let it draft an issue for you.

<details>
<summary>Bug report agent prompt</summary>

```
I want to report a bug in open-maestri. Help me write a clear, detailed bug report.

Here is what happened:
[describe what you saw]

Here is what I expected to happen:
[describe expected behavior]

Steps to reproduce:
[list the steps, as precisely as you can]

Before we write the report, please ask me the following diagnostic questions
so we can include the right environment details:

1. What version of macOS are you running?
   (System Settings → General → About → macOS version)

2. What version of Xcode do you have installed?
   (Xcode → About Xcode)

3. Run `swift --version` in Terminal and paste the output.

4. Is the open-maestri app currently running when the bug occurs,
   or does it happen during launch / shutdown?

5. Are there any crash logs?
   (open Console.app → Crash Reports, filter by "open-maestri")

6. Did the bug appear after a recent update, or has it always been present?

Once I answer these questions, format everything as a GitHub issue with:
- A short, descriptive title
- Environment section (macOS, Xcode, Swift versions)
- Steps to reproduce
- Expected behavior
- Actual behavior
- Any relevant logs or screenshots placeholder

Then show me the formatted issue text so I can copy it to GitHub.
```

</details>

---

### Request a Feature via Your Code Agent

Have an idea? Paste this prompt to help your agent shape it into a proper feature request.

<details>
<summary>Feature request agent prompt</summary>

```
I want to request a new feature for open-maestri. Help me write a clear,
well-scoped feature request.

My idea:
[describe what you want]

Before writing the request, please ask me:

1. What problem does this solve, or what workflow does it improve?
2. How would a user trigger this feature (keyboard shortcut, menu item,
   canvas gesture, omaestri CLI command)?
3. Does this need to work across agent sessions, or is it session-local?
4. Are there similar features in the existing codebase I should reference?
   (You can check CLAUDE.md and the Sources/ directory for clues.)
5. Is this additive (new behavior) or does it change existing behavior?

After I answer, please:
- Read CLAUDE.md to check if this conflicts with any existing constraints
  (especially the "not implementing Ombro" note and platform targets)
- Draft a GitHub feature request issue with: title, motivation, proposed UX,
  scope notes, and any open questions
- Flag any parts that seem out of scope or technically risky
```

</details>

---

## Agent Parts

*This section is written for agents.*

### About the Project

open-maestri is a macOS application providing an infinite canvas where AI agent terminals, browser portals, markdown notes, and file trees co-exist as draggable nodes. Nodes communicate through the `omaestri` CLI — a local HTTP server embedded in the app that lets terminals send messages to each other and to the canvas. The data format is compatible with Maestri v0.25.4.

The canvas engine is AppKit (`NSView`). All UI outside the canvas is SwiftUI. The two layers bridge via `NSViewRepresentable`. State management uses `@Observable` (Swift 5.9+, not `ObservableObject`). There is no iOS code.

### Prerequisites

| Tool | Minimum version |
|------|----------------|
| macOS | 14.0 (Sonoma) |
| Xcode | 16.0 |
| Swift | 5.9 (bundled with Xcode) |

Verify your environment:

```bash
swift --version
xcodebuild -version
```

Clone and let SPM resolve dependencies automatically (SwiftTerm, Sparkle):

```bash
git clone https://github.com/your-org/open-maestri.git
cd open-maestri
```

### Build & Test

```bash
# Development build
swift build

# Open in Xcode (recommended for UI work)
open Package.swift

# Run all tests
swift test

# Run a specific test
swift test --filter OpenMaestriTests.WorkspaceManagerTests/testCreateWorkspace

# CI-equivalent build (no code signing)
xcodebuild -scheme open-maestri \
  -destination 'platform=macOS' \
  test \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO
```

Commit convention: `<type>: <short description>` — types are `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`.

### Where to Go Next

| Document | What it covers |
|----------|---------------|
| `CLAUDE.md` | Architecture overview, coding constraints, data formats, IPC protocol |
| `docs/reference/maestri-reference-index.md` | Canvas UI spec, node types, keyboard shortcuts |
| `Sources/InterAgent/` | `omaestri` CLI server and command routing — start here for new CLI commands |
| `Sources/Canvas/` | Canvas viewport, node rendering, drag and zoom |
| `Sources/Workspace/` | Persistence, serialization, `workspace.json` schema |
