# Connections

Connections are one of Maestri's core features. They link terminals and notes together with physics-animated cables, and they unlock real communication between agents — across any CLI tool.

## Inter-agent communication

When two terminals are connected, Maestri installs a **Maestri Agent Skill** in each one. This skill gives agents the ability to send prompts to, and receive responses from, any other connected agent.

Any agent that starts inside Maestri will automatically know how this works. You can prompt one agent to ask another:

> "Ask the Reviewer to look at the current implementation."

Since the skill works at the CLI level, it's **agent-agnostic** — Claude Code can talk to Codex, OpenCode can talk to Claude, any combination works.

> Tip: If an agent doesn't load the Maestri skill automatically, you can nudge it: _"Use maestri to ask [Agent Name]..."_

## Keep the receiving agent unselected

When one agent sends a prompt to another, **leave the receiving agent unselected** (no dashed border around it). Maestri only monitors terminals that aren't currently focused. When the receiving agent finishes generating its response, Maestri detects this and sends the answer back to the original agent.

If you select the receiving agent, Maestri assumes you want to take manual control and stops monitoring it — which means the waiting agent will never get its response.

## Creating a connection

**Method 1 — Toolbar:** Select a terminal, then click the **Connection** tool in the toolbar. A line follows your cursor. Click the second terminal (or note) to complete the connection.

**Method 2 — Keyboard shortcut:** With a terminal selected, press `L` to start a connection from the keyboard.

A rope-like cable with physics animation links the two nodes. You can have multiple connections on any terminal.

## Agent-note connections

You can connect a terminal to a **note** instead of another terminal. When connected, the agent can read and edit the note's content through the Maestri CLI.

Think of it as giving the agent a persistent notebook — a shared place where you can both write things down that survive across sessions, night sleeps, and agent restarts.

## Agent-portal connections

You can connect a terminal to a **portal** — an embedded browser living on the canvas. Once connected, the agent can control the browser programmatically: navigate pages, click elements, fill forms, take screenshots, read the DOM, and more.

No external dependencies or configuration — just connect and the agent gets full browser automation out of the box.

## Note chaining

Notes can be connected to other notes, forming a **chain** (or tree). You only need to connect the entry-point note to the agent — the agent can then traverse the entire chain.

This creates a mind-map-like structure: you can organize information hierarchically across multiple notes, and the agent understands the hierarchy automatically.
