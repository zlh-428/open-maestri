// Sources/CLI/main.swift
import Foundation

// 1. 读取环境变量
guard let socketPath = ProcessInfo.processInfo.environment["MAESTRI_SOCKET"] else {
    fputs("only available inside open-maestri terminals (MAESTRI_SOCKET not set).\n", stderr)
    exit(1)
}
guard let terminalId = ProcessInfo.processInfo.environment["MAESTRI_TERMINAL_ID"] else {
    fputs("only available inside open-maestri terminals (MAESTRI_TERMINAL_ID not set).\n", stderr)
    exit(1)
}

// 2. 解析命令
let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    printHelp()
    exit(1)
}

// 3. 命令分发
switch command {
case "list":
    ListCommand.run(args, socketPath, terminalId)
case "ask":
    AskCommand.run(args, socketPath, terminalId)
case "check":
    CheckCommand.run(args, socketPath, terminalId)
case "note":
    NoteCommand.run(args, socketPath, terminalId)
case "portal":
    PortalCommand.run(args, socketPath, terminalId)
case "recruit", "dismiss", "connect":
    MaestroCommands.run(args, socketPath, terminalId)
case "role":
    RoleCommand.run(args, socketPath, terminalId)
case "preset":
    PresetCommand.run(args, socketPath, terminalId)
case "debug":
    DebugCommand.run(args, socketPath, terminalId)
case "-h", "--help", "help":
    printHelp()
    exit(0)
default:
    fputs("error: unknown command '\(command)'. Try 'omaestri list' for available commands.\n", stderr)
    exit(1)
}
