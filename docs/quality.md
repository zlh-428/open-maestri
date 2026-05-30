# Quality Assurance

## Purpose

Documents the current quality assurance practices, known gaps, and improvement directions for open-maestri, for developers and AI agents to understand the testing landscape.

---

## Common Commands

```bash
# Development build
swift build

# Release build
swift build -c release

# Xcode CI build (no signing required)
xcodebuild -scheme open-maestri -destination 'platform=macOS' build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

# Run all unit tests
swift test

# Run a single test
swift test --filter OpenMaestriTests.WorkspaceManagerTests/testCreateWorkspace

# Dev debug: watch build artifacts, auto-bundle and launch .app
bash scripts/dev.sh
```

---

## Current Coverage

### Unit Tests (`Tests/OpenMaestriTests/`)

Covers the following modules across 21 test files:

| Module | Test Files |
|--------|-----------|
| Canvas | `CanvasNodeRendererTests`, `CanvasViewportTests`, `RopePathRendererTests`, `RopeSimulationTests`, `TileSnappingTests` |
| Connection | `ConnectionManagerTests`, `SkillInjectorTests` |
| Floor | `FloorManagerTests` |
| InterAgent | `AgentMatchingTests`, `CLIRouterTests`, `InterAgentServerTests` |
| Note | `NoteFileManagerTests` |
| Routine | `RoutineSchedulerTests` |
| Terminal | `TerminalSessionTests` |
| Workspace | `AutosaveTests`, `CGRectFrameTests`, `CanvasNodeLegacyDecodeTests`, `MigrationTests`, `PersistenceManagerTests`, `WorkspaceLifecycleTests`, `WorkspaceManagerTests` |

Core business logic (persistence, serialization, CLI routing, connection management) has basic unit test coverage.

### CLI Acceptance Test Documentation

`docs/cli-acceptance-test.md` documents the manual acceptance test steps for `omaestri` CLI commands. `docs/cli-acceptance-test-out.md` stores a snapshot of one actual execution run, which can serve as a regression baseline for comparison.

---

## Known Gaps

The following are known, **unresolved** quality gaps, listed honestly to guide future improvement:

| Gap | Description |
|-----|-------------|
| **No automated smoke tests** | No script automatically launches the app after a build and verifies basic functionality; CLI acceptance tests are still executed manually |
| **No CI configuration** | The CI badge in the README points to a non-existent GitHub Actions workflow — no automated builds or tests are actually triggered |
| **No GUI automation** | Canvas interactions, node dragging, Portal rendering, and other UI paths rely entirely on manual testing; no XCTest UI or screenshot regression coverage exists |
| **No docs structure validation** | No script verifies the completeness or formatting consistency of documents in the `docs/` directory |
| **Test coverage not quantified** | No coverage report is configured (e.g. `llvm-cov`); it is unclear whether actual coverage meets any target threshold |

---

## Improvement Recommendations

In priority order:

1. **Fix or remove the CI badge**: Add a minimal working GitHub Actions workflow (`swift build` + `swift test`), or remove the badge pointing to a non-existent workflow from the README to avoid misleading contributors.
2. **Add a smoke script**: `scripts/smoke.sh` should build the Release binary, launch the app, verify process startup, IPC port binding, and that `omaestri ping` returns successfully — runnable in CI.
3. **Quantify coverage**: Add `swift test --enable-code-coverage` to CI and generate a report with `llvm-cov report`; establish an 80% baseline target.
4. **Automate CLI acceptance tests**: Convert the steps in `docs/cli-acceptance-test.md` into an executable script to replace manual execution.
