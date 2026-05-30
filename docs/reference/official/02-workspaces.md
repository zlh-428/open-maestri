# Workspaces

A workspace is Maestri's equivalent of a project. It remembers your canvas layout, terminal positions, agent assignments, and settings — so picking up where you left off is instant.

## Creating a workspace

Click the **+** button in the sidebar to create a new workspace. You'll be asked for two things:

- **Working directory** — The root folder for this project. New terminals will open here by default.
- **Icon** — A small icon to help you identify the workspace at a glance in the sidebar.

Once created, the workspace appears in the sidebar and opens automatically.

> Tip: Workspaces run in the background when you switch away. You can have multiple workspaces active at the same time and switch between them freely.

## Editing a workspace

Right-click any workspace entry in the sidebar and choose **Edit** to update its name, icon, working directory, or agent instructions.

## CLAUDE.md and AGENTS.md

From the workspace edit screen, you can manage `CLAUDE.md` and `AGENTS.md` files. These files contain instructions that agents automatically receive when they start inside that workspace — a great place to define project conventions, context, or any standing instructions you'd otherwise repeat every session.

Since Claude Code only understands `CLAUDE.md` while most other agents have standardized on `AGENTS.md`, Maestri includes an option to keep both files in sync automatically. Enable it in the workspace settings if you run mixed agent setups.

## Folders and groups

As your workspace list grows, you can organize it two ways:

- **Folders** — Group related workspaces (e.g., different services in the same system). Useful when workspaces share a project but have different working directories.
- **Groups** — Section dividers in the sidebar with a label. Useful for separating unrelated categories, like personal and work projects.

## Open in editor

A button in the top-right corner of the app lets you open the current workspace's working directory directly in your code editor.

## Spotlight integration

All your workspaces are indexed system-wide on macOS through native Spotlight integration. Open Spotlight and search for a specific terminal window or note content — the result takes you directly to it inside Maestri.

## Workspace shortcuts

Maestri is built for fast context switching. Three ways to navigate between workspaces:

### Arrow keys

`⌘↑` or `⌘↓` moves to the previous or next workspace in sidebar order.

### Number shortcuts

Double-tap `⌘` and the sidebar icons are temporarily replaced by numbers. Press any number to jump to that workspace immediately.

You can assign a custom number to each workspace in its settings. Reserve this feature for your most-visited workspaces — it's the fastest way to switch.

### Trackpad and mouse

Hold `⌘` and swipe up or down with two fingers (trackpad) or the scroll wheel (mouse) to cycle through workspaces.

> Tip: All shortcut bindings — including these — are customizable in the app's Settings.
