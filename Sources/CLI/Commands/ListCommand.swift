// Sources/CLI/Commands/ListCommand.swift
import Foundation

enum ListCommand {
    static func run(_ args: [String], _ socketPath: String, _ terminalId: String) {
        let response = Transport.send(args: args, socketPath: socketPath, terminalId: terminalId)
        print(response)
    }
}
