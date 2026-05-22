import Foundation
import OSLog

final class CheckHandler {
    static let shared = CheckHandler()
    private let logger = Logger.make(category: "CheckHandler")
    private init() {}

    func handle(args: [String], terminalId: UUID?) -> String {
        runOnDetached { await self.handleAsync(args: args, terminalId: terminalId) }
    }

    @MainActor
    func handleAsync(args: [String], terminalId: UUID?) async -> String {
        guard args.count >= 2 else {
            return "error: usage: omaestri check \"TargetAgent\" [lines]"
        }
        let targetName = args[1]
        let lineCount = args.count >= 3 ? Int(args[2]) ?? 20 : 20

        guard let callerTid = terminalId else { return "error: missing terminal ID" }
        let tm = TerminalManager.shared
        let cm = ConnectionManager.shared
        let connectedIds = cm.connectedNodeIds(for: callerTid)
        let lower = targetName.lowercased()
        let targetSession = tm.terminals.values.first { session in
            guard connectedIds.contains(session.id) else { return false }
            return session.agentName?.lowercased().contains(lower) == true ||
                   session.displayName?.lowercased().contains(lower) == true ||
                   session.command.lowercased().contains(lower) ||
                   session.id.uuidString.hasPrefix(targetName)
        }
        guard let session = targetSession else {
            return "error: agent '\(targetName)' not found in connections"
        }
        let output = session.recentOutput(lines: lineCount)
        return output.isEmpty ? "(no recent output)" : output
    }

    private func runOnDetached(_ block: @escaping () async -> String) -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var result = ""
        Task.detached { result = await block(); semaphore.signal() }
        semaphore.wait()
        return result
    }
}
