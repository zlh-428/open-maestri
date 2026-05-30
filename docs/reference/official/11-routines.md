# Routines

Routines let you automate repetitive tasks in your workspace by scheduling prompts that run on your agents at set intervals. Instead of manually typing the same commands throughout the day, define a routine and let Maestri handle it for you.

## Why Routines?

Many development workflows involve repetitive actions — running tests, checking build status, pulling the latest changes, or asking an agent to review recent commits. Routines turn these into hands-free automations that run in the background while you focus on deeper work.

## Creating a routine

1. Go to **File → Routines** in the menu bar.
2. Click **New Routine**.
3. Write the prompt you want to send to your agent.
4. Set the interval (e.g., every 5 minutes, every hour).
5. Select which agent terminal should receive the prompt.
6. Click **Save**.

The routine starts running immediately and will continue at the specified interval until you pause or delete it.

## Chaining commands

You can chain multiple prompts in a single routine by separating them with `&&` on its own line. Each prompt is sent as a new message to the agent — the next one only fires after the previous one completes.

For example:

```
pull the latest changes
&&
run the test suite
&&
summarize the results
```

This sends three separate messages to the agent, one after the other — all from a single routine.

## Managing routines

- **Pause / Resume** — Toggle a routine on or off without deleting it.
- **Edit** — Change the prompt, interval, or target agent at any time.
- **Delete** — Remove a routine permanently.

Active routines show a live indicator so you can see at a glance what's running.

## Use cases

- **Continuous testing** — Run your test suite every few minutes to catch regressions early.
- **Status monitoring** — Ask an agent to check deployment status or server health on a schedule.
- **Code review loops** — Have a reviewer agent periodically scan for new commits and leave feedback.
- **Multi-step workflows** — Chain build, test, and deploy commands into a single automated pipeline.
- **Web automations** — Connect an agent to a browser portal and schedule it to check a dashboard, scrape data from a page, or fill out forms on a recurring basis.
- **Scheduled scraping** — Have an agent open a portal, extract information from a live page, and write the results to a note — all on autopilot.
