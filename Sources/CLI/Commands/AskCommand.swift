// Sources/CLI/Commands/AskCommand.swift
import Foundation

enum AskCommand {
    static func run(_ args: [String], _ socketPath: String, _ terminalId: String) {
        guard args.count >= 3 else {
            fputs("error: usage: omaestri ask \"Agent Name\" \"prompt\"\n", stderr)
            exit(1)
        }
        let response = Transport.send(args: args, socketPath: socketPath, terminalId: terminalId)
        print(response)
    }
}
