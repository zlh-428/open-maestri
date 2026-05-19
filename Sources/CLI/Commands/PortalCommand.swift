// Sources/CLI/Commands/PortalCommand.swift
import Foundation

enum PortalCommand {
    static func run(_ args: [String], _ socketPath: String, _ terminalId: String) {
        guard args.count >= 2 else {
            fputs("error: usage: omaestri portal <subcommand> ...\n", stderr)
            fputs("  Subcommands: create edit navigate screenshot snapshot html text info\n", stderr)
            fputs("               click fill type key hover scroll drag wait evaluate\n", stderr)
            exit(1)
        }
        let response = Transport.send(args: args, socketPath: socketPath, terminalId: terminalId)
        print(response)
    }
}
