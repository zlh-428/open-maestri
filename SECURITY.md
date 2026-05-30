# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest release | ✅ |
| Older releases | ❌ |

We only provide security fixes for the **latest release**. Please upgrade before reporting.

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities via public GitHub Issues.**

Instead, use one of the following private channels:

- **GitHub Private Security Advisory** (preferred):  
  [https://github.com/zlh-428/open-maestri/security/advisories/new](https://github.com/zlh-428/open-maestri/security/advisories/new)

### What to Include

Please provide as much detail as possible:

- Description of the vulnerability
- Steps to reproduce (proof-of-concept if available)
- Affected version(s)
- Potential impact

### Response Timeline

| Stage | Time |
|-------|------|
| Initial acknowledgement | Within **72 hours** |
| Status update | Within **7 days** |
| Fix / patch release | Depends on severity |

### Disclosure Policy

We follow **responsible disclosure**. We ask that you:

1. Give us reasonable time to investigate and fix the issue before public disclosure
2. Avoid accessing or modifying other users' data during testing
3. Act in good faith

We will credit researchers who responsibly disclose vulnerabilities in the release notes (unless you prefer to remain anonymous).

## Scope

Issues **in scope**:

- Remote code execution
- Privilege escalation
- Data leakage from the canvas or workspace files
- IPC / Unix Socket authentication bypass (`omaestri` CLI protocol)

Issues **out of scope**:

- Vulnerabilities in third-party dependencies (report to upstream)
- Issues requiring physical access to the machine
- Social engineering attacks

## Security-Related Configuration

open-maestri communicates locally via:

- **TCP** `127.0.0.1` on a dynamic port
- **Unix Socket** at `~/.open-maestri/run/agent.sock`

Both channels are local-only and not exposed to the network by default. Ensure your `~/.open-maestri/` directory has appropriate permissions (`700`).
