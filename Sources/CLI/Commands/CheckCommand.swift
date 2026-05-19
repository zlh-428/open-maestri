// Sources/CLI/Commands/CheckCommand.swift
import Foundation

enum CheckCommand {
    static func run(_ args: [String], _ socketPath: String, _ terminalId: String) {
        guard args.count >= 2 else {
            fputs("error: usage: omaestri check \"Agent Name\" [lines]\n", stderr)
            exit(1)
        }
        let response = Transport.send(args: args, socketPath: socketPath, terminalId: terminalId)
        print(response)
    }
}
