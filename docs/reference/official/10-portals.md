# Portals

Portals are embedded browser windows that live right on your canvas. They let you browse websites, preview local files, and even let your AI agents interact with web pages directly.

## Creating a portal

Click the **Portal** button in the toolbar (globe icon) or press `P` to add a new portal to your canvas. Enter a URL — any website like `https://example.com`.

Each portal runs an isolated WebKit (Safari) instance with its own storage. Chrome support is planned for the future.

## Connecting portals

You can connect a portal to another portal so they share the same storage session. This is useful when one portal needs to access cookies or authentication state from another.

Use the connection tool to link portals together, just like all other nodes on the canvas.

## Agent automation

When a portal is connected to an agent's terminal, the agent can control it programmatically using the `maestri` CLI. No external dependencies, no MCP servers, no configuration — just connect and go. Like everything in Maestri, it's plug and play.

Portal automation is a custom-designed browser-use tool built for speed and token efficiency. Agents can:

- **Click, type, and scroll** — interact with any element on the page
- **Navigate** — go to URLs, go back, refresh
- **Take screenshots** — see the page visually, just like you do
- **Run JavaScript** — execute custom scripts in the page context
- **Read the DOM** — inspect the page structure
- **See the browser console** — catch errors and debug output

Agents can also **create new portals** on their own — they don't need you to place one manually.

To allow an agent to control a portal, connect them using the connection tool. Agents can see chained portals and control all of them.

> Tip: Since portals run isolated browser instances, you can have multiple logged-in sessions to the same service simultaneously — useful for testing different user accounts.
