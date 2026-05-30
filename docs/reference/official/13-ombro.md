# Ombro

Ombro is an on-device AI companion that keeps an eye on your agents while you do other things. It lives in a floating window outside the app — always reachable, never in the way.

## Monitoring agents

Ombro watches your running agents passively. When an agent finishes a task or reaches a stopping point, Ombro notifies you with a summary of what happened, a snapshot preview of the terminal's current state, and suggested next actions — so you can decide what to do without switching back to Maestri and reading through the output yourself.

## Asking about an agent

You can query Ombro directly at any time:

> "Check what Codex is doing."

> "Is the Reviewer still running?"

Ombro reads the live terminal state and gives you a concise answer. Useful when you're in another app and want a quick status without context-switching.

## Adding notes

Ombro can create a note called **Ombro Notes** in your workspace and add new entries to it through natural language:

> "Add a note saying we still need to write tests for the auth module."

> "Note that the API rate limit issue is resolved."

The note is created automatically on the canvas the first time, and appended to on subsequent requests.

## Summarizing notes

Ombro can read and summarize notes across the entire workspace:

> "Summarize my notes."

It traverses all notes connected in the current workspace and gives you a coherent overview — handy for catching up after a break or sharing context with a new agent.

## Powered by Apple Foundation Models

Ombro runs entirely on your Mac using Apple Foundation Models. No API calls, no cloud, no latency. Your code and terminal output never leave your machine.

> Note: Apple Foundation Models require a Mac with Apple Silicon running macOS Tahoe 26 or later.

## Opening Ombro

Press `⇧O` to open or dismiss the Ombro window.
