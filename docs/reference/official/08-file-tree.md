# File Tree

The File Tree node lets you browse your project's files right on the canvas — no need to switch to Finder or your IDE. It's a fully featured file manager embedded in your workspace.

## Inserting a File Tree node

Select the **File Tree** tool in the top toolbar, then click and drag on the canvas to place it. The file tree opens at your workspace's working directory by default.

You can have **multiple file trees** on the same canvas, and each one independently remembers its own state — which directory it's showing, which folders are expanded, and which view mode is active.

## View modes

Switch between two views using the toolbar at the top of the file tree node:

- **List view** — A hierarchical outline, similar to macOS Finder's list view. Supports back/forward navigation and Collapse All.
- **Icon grid** — A thumbnail-based view. Images, PDFs, and videos show Quick Look previews instead of generic icons.

## Navigating files

Use the toolbar to change the root directory on the fly. Right-clicking a file or folder opens a context menu with options to create, rename, move, and delete.

## Dragging files

You can drag files from the file tree directly onto:

- **An agent terminal** — Shares the file as context with the agent
- **The canvas** — Places it as a native preview node (images, PDFs, and videos are supported)

> Tip: You can also drag external files from Finder directly onto an agent terminal or onto the canvas — you don't have to use the file tree for this.

## Git operations

When your workspace is a git repository, the file tree includes a branch indicator at the top. Click it to open a menu with common git operations:

- **Commit** — Stage and commit changes
- **Pull / Push** — Sync with your remote repository
- **Checkout** — Switch to a different branch
- **New Branch** — Create a new branch from the current one
- **Merge** — Merge another branch into the current one
- **Fetch** — Fetch updates from the remote without merging
- **Stash** — Stash your uncommitted changes for later

These operations run directly in Maestri — no need to switch to a terminal or external git client for common tasks.

## Diff view with agent integration

The file tree includes a built-in diff view that shows your uncommitted changes. Beyond reviewing diffs, it integrates directly with your agents — select any code block in the diff and a chat icon will appear. Click it to open a popover where you can quote the selected block and ask an agent to explain or refine it.
