// Sources/CLI/Commands/DebugCommand.swift
import Foundation

enum DebugCommand {
    static func run(_ args: [String], _ socketPath: String, _ terminalId: String) {
        print("=== open-maestri CLI Diagnostics ===\n")
        print("Terminal ID:      \(terminalId)")
        print("Socket:           \(socketPath)\n")

        // 检查 socket 文件是否存在且类型正确
        var st = stat()
        let statResult = stat(socketPath, &st)
        let exists = FileManager.default.fileExists(atPath: socketPath)
        if !exists {
            print("Socket exists:    no\n")
        } else if statResult == 0 && (st.st_mode & S_IFMT) == S_IFSOCK {
            print("Socket exists:    yes (unix socket)\n")
        } else {
            print("Socket exists:    yes (not a socket — wrong file type)\n")
        }

        print("Testing connection...")
        let response = Transport.send(args: ["debug"], socketPath: socketPath, terminalId: terminalId)
        if response.hasPrefix("error") {
            print("Connection:       FAILED\nError: \(response)")
        } else {
            print("Connection:       OK\n")
        }

        let binaryPath = ProcessInfo.processInfo.environment["MAESTRI_CLI"]
            ?? CommandLine.arguments[0]
        print("Binary:           \(binaryPath)")
        print("PATH:             \(ProcessInfo.processInfo.environment["PATH"] ?? "(not set)")")

        print("""

=== Troubleshooting ===

If "Socket exists: no":
  → The open-maestri app may not be running, or this terminal was launched outside open-maestri.

If "Connection: FAILED":
  → Try restarting the terminal from within open-maestri. The socket may have gone stale.

If "omaestri: command not found":
  → Your shell resets PATH. Use "$MAESTRI_CLI" instead of "omaestri".
""")
    }
}
