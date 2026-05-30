# open-maestri Git Worktree Workflow

## Goals

- Keep `main` always green and buildable — never commit broken Swift directly to main
- Isolate each feature, fix, or investigation in its own worktree so Xcode indexing and `swift build` in one topic do not interfere with another
- Allow parallel workstreams (e.g. canvas engine refactor alongside CLI handler additions) without branch-switching overhead
- Establish clear merge boundaries: a topic worktree is only integrated back to main after it builds cleanly and passes `swift test`

---

## Repository

```
https://github.com/your-org/open-maestri
```

---

## Roles

### Integration worktree (main checkout)

```
~/Projects/open-maestri/          # the original clone, tracks main
```

This is the single source of truth. It is the only place where:

- `git merge` or `git rebase` onto `main` is performed
- Release tags are created
- The final `swift build -c release` verification runs before a push to `main`

Never do exploratory or feature work directly here.

### Topic worktrees

```
~/Projects/open-maestri-<topic>/  # sibling directory per branch
```

Each topic worktree is a separate directory with its own working tree but shares the same `.git` object store. Xcode and `swift build` can run independently in each without disturbing the others.

---

## Standard Lifecycle

### 1. Create a topic worktree

```bash
# From the integration worktree
cd ~/Projects/open-maestri

# Fetch latest
git fetch origin

# Create worktree on a new branch based on main
git worktree add ../open-maestri-<topic> -b feat/<topic> origin/main

# Enter the worktree
cd ../open-maestri-<topic>
```

Branch naming conventions:

| Prefix | Use |
|---|---|
| `feat/<topic>` | New capability or user-visible feature |
| `fix/<topic>` | Bug fix |
| `docs/<topic>` | Documentation only |
| `investigate/<topic>` | Spike, experiment, or proof-of-concept |

### 2. Work in the topic worktree

```bash
cd ~/Projects/open-maestri-<topic>

# Build check after each meaningful change
swift build

# Run tests
swift test

# Commit freely — main is untouched
git add -p
git commit -m "feat(canvas): add rubber-band selection hit testing"
```

Keep commits small and buildable. Each commit on the topic branch should pass `swift build` on its own.

### 3. Integrate back to main

```bash
# Ensure the topic is up to date with main before integrating
cd ~/Projects/open-maestri-<topic>
git fetch origin
git rebase origin/main

# Final build + test verification in the topic worktree
swift build
swift test

# Switch to the integration worktree
cd ~/Projects/open-maestri

# Merge (fast-forward preferred; use --no-ff only when a merge commit is desired for history clarity)
git merge feat/<topic> --ff-only

# Or for a topic with multiple commits worth preserving as a unit:
git merge feat/<topic> --no-ff -m "feat(canvas): rubber-band selection (#42)"

# Verify once more in main
swift build
swift test

# Push
git push origin main
```

### 4. Cleanup

```bash
# Remove the worktree directory
git worktree remove ../open-maestri-<topic>

# Delete the local branch
git branch -d feat/<topic>

# Delete the remote branch if it was pushed
git push origin --delete feat/<topic>
```

---

## Push Policy

| Branch | Who pushes | When |
|---|---|---|
| `main` | Integration worktree only | After merge + full build/test pass |
| `feat/*`, `fix/*`, `docs/*` | Topic worktree | For backup, code review, or CI; optional |
| `investigate/*` | Topic worktree | Optional; delete after spike concludes |

Never force-push `main`.

---

## Recommended Conventions

- **One concern per worktree.** Do not mix a canvas refactor and a CLI addition in the same topic branch. Split them.
- **Rebase before merge.** Always rebase the topic branch onto the latest `main` before merging back, so the integration stays linear.
- **Build gate.** `swift build` must succeed in the topic worktree before any merge into `main`. `swift test` must also pass.
- **Worktree naming mirrors branch name.** `feat/note-linking` → `open-maestri-note-linking`. This makes it obvious which directory belongs to which branch.
- **Short-lived topics.** Topics should be open for days, not weeks. If a topic grows large, split it into smaller mergeable slices.
- **No Xcode project file conflicts.** Because each worktree has its own directory, Xcode derived data and index caches are naturally isolated. Do not share a derived data path across worktrees.

---

## Suggested Workstream Layout

The following shows a realistic parallel workstream arrangement for open-maestri subsystems:

```
~/Projects/
├── open-maestri/                        # integration worktree — main branch
├── open-maestri-canvas-engine/          # feat/canvas-engine — rubber-band, zoom, hit testing
├── open-maestri-cli-handlers/           # feat/cli-handlers — new omaestri subcommands
├── open-maestri-note-system/            # feat/note-system — note linking, frontmatter
├── open-maestri-connection-layer/       # feat/connection-layer — SkillInjector, ConnectionManager
├── open-maestri-fix-ipc-timeout/        # fix/ipc-timeout — InterAgentServer edge case
└── open-maestri-investigate-floors/     # investigate/floors — git worktree isolation spike
```

### Subsystem ownership hints

| Worktree topic | Primary paths in repo |
|---|---|
| `canvas-engine` | `Sources/Canvas/` |
| `cli-handlers` | `Sources/InterAgent/Handlers/`, `Sources/InterAgent/CLIRouter.swift` |
| `note-system` | `Sources/Workspace/Models/`, `~/.open-maestri/workspaces/*/notes/` |
| `connection-layer` | `Sources/Connection/`, `Sources/InterAgent/InterAgentServer.swift` |
| `terminal` | `Sources/Terminal/` |
| `persistence` | `Sources/Workspace/PersistenceManager.swift` |

---

## Quick Reference

```bash
# List all worktrees
git worktree list

# Create topic worktree
git worktree add ../open-maestri-<topic> -b <prefix>/<topic> origin/main

# Remove worktree after merge
git worktree remove ../open-maestri-<topic>

# Build check (run in any worktree)
swift build

# Full test run
swift test

# Xcode CI build (no signing required)
xcodebuild -scheme open-maestri \
  -destination 'platform=macOS' build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```
