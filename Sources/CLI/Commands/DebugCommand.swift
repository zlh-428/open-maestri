// Sources/CLI/Commands/DebugCommand.swift
import Foundation

enum DebugCommand {
    static func run(_ args: [String], _ socketPath: String, _ terminalId: String) {
        print("=== open-maestri CLI Diagnostics ===")
        print("Terminal ID:   \(terminalId)")
        print("Socket:        \(socketPath)")

        // 检查 socket 文件是否存在且类型正确
        var st = stat()
        let statResult = stat(socketPath, &st)
        let exists = FileManager.default.fileExists(atPath: socketPath)
        if !exists {
            print("Socket exists: no")
        } else if statResult == 0 && (st.st_mode & S_IFMT) == S_IFSOCK {
            print("Socket exists: yes")
        } else {
            print("Socket exists: yes (not a socket — wrong file type)")
        }

        print("\nTesting connection...")
        let response = Transport.send(args: ["debug"], socketPath: socketPath, terminalId: terminalId)
        if response.hasPrefix("error") {
            print("Connection: FAILED\nError: \(response)")
        } else {
            print("Connection: OK")
            print(response)
        }

        let binaryPath = ProcessInfo.processInfo.environment["MAESTRI_CLI"]
            ?? CommandLine.arguments[0]
        print("\nBinary:  \(binaryPath)")
        print("PATH:    \(ProcessInfo.processInfo.environment["PATH"] ?? "(not set)")")

        print("""

=== Troubleshooting ===
If "Socket exists: no":
  → open-maestri may not be running, or the workspace is not active
If "Connection: FAILED":
  → Try restarting the terminal from within open-maestri
If "omaestri: command not found":
  → Use "$MAESTRI_CLI" instead of "omaestri"
""")
    }
}
