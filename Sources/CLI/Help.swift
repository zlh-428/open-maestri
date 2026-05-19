// Sources/CLI/Help.swift
import Foundation

func printHelp() {
    print("""
    omaestri — open-maestri inter-agent CLI

    Usage: omaestri <command> [args...]

    Commands:
      list                              List connected agents, notes, portals
      ask "Agent" "prompt"              Send prompt to connected agent
      check "Agent" [lines]             View agent's recent output
      note <read|write|edit|create>     Read/write connected notes
      portal <subcommand>               Interact with connected portals
      recruit "Name" [--preset x]       Recruit a new agent (Maestro only)
      dismiss "Name"                    Dismiss a recruited agent
      connect "From" "To"               Connect two agents
      role <list|create|edit|assign>    Manage agent roles
      preset list                       List available agent presets
      debug                             Diagnose connection issues

    Environment:
      MAESTRI_SOCKET       Unix socket path (set by open-maestri)
      MAESTRI_TERMINAL_ID  Terminal UUID (set by open-maestri)
      MAESTRI_CLI          Path to this binary
    """)
}
