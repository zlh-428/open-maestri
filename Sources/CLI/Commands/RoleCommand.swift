// Sources/CLI/Commands/RoleCommand.swift
import Foundation

enum RoleCommand {
    static func run(_ args: [String], _ socketPath: String, _ terminalId: String) {
        guard args.count >= 2 else {
            fputs("error: usage: omaestri role <list|create|show|edit|write|assign> [args...]\n", stderr)
            fputs("  list\n", stderr)
            fputs("  create \"RoleName\" \"Role instructions\"\n", stderr)
            fputs("  show   \"RoleName\"\n", stderr)
            fputs("  edit   \"RoleName\" --prompt \"...\"\n", stderr)
            fputs("  write  \"RoleName\" --prompt \"...\"\n", stderr)
            fputs("  assign \"AgentName\" \"RoleName\"\n", stderr)
            exit(1)
        }
        let response = Transport.send(args: args, socketPath: socketPath, terminalId: terminalId)
        print(response)
    }
}
