# Terminals & Agents

Terminals are where you and your agents get things done. Each terminal is a full interactive shell — and with coding agents running inside them, they become the primary place where work actually happens.

## Creating a terminal

1. Select the **Terminal** tool in the top toolbar.
2. Click and drag on the canvas to draw the terminal at your desired size.
3. A modal appears — select a coding agent from the preset list.

> Note: Maestri expects your agents to be installed already. For instructions on installing Claude Code, Codex, or other supported agents, refer to their respective documentation.

You can also give each terminal a **name** and **icon** to make it easy to identify at a glance, especially when you have many on the canvas.

## Roles

Roles let you define a set of instructions for a specific terminal instance. When a role is assigned, Maestri automatically injects those instructions when the agent starts — so you don't have to repeat yourself every session.

**Example roles:**

- _Lead_ — Sets the agent as the coordinator that delegates to others
- _Coder_ — Focuses the agent purely on implementation
- _Reviewer_ — Instructs the agent to review and critique code
- _Tester_ — Focuses the agent on writing and running tests

### Managing roles

Go to **Settings → Agents** to create, edit, and organize roles. Each role has a name, a color badge, and a set of instructions. Assign a role when creating a terminal or later via right-click.

Roles work by starting the agent in a project subdirectory with its own `CLAUDE.md` / `AGENTS.md`, so each agent can have unique instructions. Maestri manages these files automatically as you assign and remove roles.

> Note: Consider adding the `.maestri` directory to your `.gitignore` if you collaborate with others on the same repository, as roles are not shareable at this time.

> Tip: The `maestri list` command (available to connected agents) shows each agent's assigned role, so agents know who they're talking to.

## Jumping between terminals

When your canvas has many terminals, keyboard navigation is essential.

Hold `⌘` — a number badge appears in the header of each terminal. While holding `⌘`, press the number to instantly focus that terminal.

Master this shortcut and you can switch between 9 agents nearly simultaneously without touching the mouse.

## Removing a terminal

To remove a terminal from the canvas, select it and press `⌘W`. This closes the terminal and removes it from the canvas.
