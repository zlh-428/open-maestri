# Remote SSH

Maestri supports connecting to remote servers via SSH, enabling inter-agent communication across machines or isolated environments.

## Enabling SSH

1. Go to **Settings > General > Remote SSH**.
2. Click **Configure**.
3. Toggle **Enable SSH workspaces**.
4. Optionally adjust the **Tunnel Port** (default: 7433).

## How it works

When you connect to an SSH workspace, Maestri installs a small script on the remote server and opens a reverse tunnel so agents can communicate back.

The script is a simple curl wrapper — you can inspect it anytime. No background processes are installed.

## Per-connection settings

When configuring SSH for a workspace or terminal, you can customize:

- **Host** — hostname or IP address
- **User** — SSH username
- **Port** — SSH port (default: 22)
- **Script Path** — where the maestri script is installed (default: `~/.local/bin/maestri`)
- **Add to PATH** — whether to add the script directory to your shell profile

## Security notes

- Uses your existing SSH keys from `~/.ssh`
- Tunnel only binds to localhost — remote access requires the SSH connection
- First-time host keys are auto-accepted; changed keys trigger a warning
