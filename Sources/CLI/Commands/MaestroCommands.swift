// Sources/CLI/Commands/MaestroCommands.swift
import Foundation

enum MaestroCommands {
    static func run(_ args: [String], _ socketPath: String, _ terminalId: String) {
        guard let command = args.first else { exit(1) }
        switch command {
        case "recruit":
            guard args.count >= 2 else {
                fputs("error: usage: omaestri recruit \"Name\" [--preset <type>] [--role <name>] [--command <cmd>]\n", stderr)
                exit(1)
            }
        case "dismiss":
            guard args.count >= 2 else {
                fputs("error: usage: omaestri dismiss \"Name\"\n", stderr)
                exit(1)
            }
        case "connect":
            guard args.count >= 3 else {
                fputs("error: usage: omaestri connect \"From\" \"To\"\n", stderr)
                exit(1)
            }
        default:
            break
        }
        let response = Transport.send(args: args, socketPath: socketPath, terminalId: terminalId)
        print(response)
    }
}
