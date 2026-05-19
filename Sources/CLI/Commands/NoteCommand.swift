// Sources/CLI/Commands/NoteCommand.swift
import Foundation

enum NoteCommand {
    static func run(_ args: [String], _ socketPath: String, _ terminalId: String) {
        guard args.count >= 2 else {
            fputs("error: usage: omaestri note <read|write|edit|create> ...\n", stderr)
            fputs("  read   \"Name\" [offset] [limit]\n", stderr)
            fputs("  write  \"Name\" \"content\"\n", stderr)
            fputs("  edit   \"Name\" \"oldText\" \"newText\"\n", stderr)
            fputs("  create [\"initial content\"]\n", stderr)
            exit(1)
        }
        let sub = args[1]
        switch sub {
        case "read":
            guard args.count >= 3 else {
                fputs("error: usage: omaestri note read \"Name\" [offset] [limit]\n", stderr)
                exit(1)
            }
        case "write":
            guard args.count >= 4 else {
                fputs("error: usage: omaestri note write \"Name\" \"content\"\n", stderr)
                exit(1)
            }
        case "edit":
            guard args.count >= 5 else {
                fputs("error: usage: omaestri note edit \"Name\" \"oldText\" \"newText\"\n", stderr)
                exit(1)
            }
        case "create":
            break
        default:
            fputs("error: unknown note subcommand '\(sub)'. Valid: read|write|edit|create\n", stderr)
            exit(1)
        }
        let response = Transport.send(args: args, socketPath: socketPath, terminalId: terminalId)
        print(response)
    }
}
