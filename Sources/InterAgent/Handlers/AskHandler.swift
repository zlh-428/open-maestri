import Foundation
import OSLog

final class AskHandler {
    static let shared = AskHandler()
    private let logger = Logger.make(category: "AskHandler")
    /// 最长等待响应时间（秒）
    private let responseTimeout: TimeInterval = 30
    /// 空闲判定：PTY 输出静止超过此时间视为响应完成
    private let idleThreshold: TimeInterval = 2.0
    private init() {}

    func handle(args: [String], terminalId: UUID?) -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var result = ""
        Task.detached { result = await self.handleAsync(args: args, terminalId: terminalId); semaphore.signal() }
        semaphore.wait()
        return result
    }

    @MainActor
    func handleAsync(args: [String], terminalId: UUID?) async -> String {
        guard args.count >= 3 else {
            return "error: usage: omaestri ask \"TargetAgent\" \"prompt\""
        }
        let targetName = args[1]
        let prompt = args[2]
        guard let callerTid = terminalId else { return "error: missing terminal ID" }

        let tm = TerminalManager.shared
        let cm = ConnectionManager.shared
        let connectedIds = cm.connectedNodeIds(for: callerTid)
        // 匹配优先级：agentName（Maestro 招募设置）> command 名称 > UUID 前缀
        guard let targetSession = tm.terminals.values.first(where: { session in
            guard connectedIds.contains(session.id) else { return false }
            let lower = targetName.lowercased()
            return session.agentName?.lowercased().contains(lower) == true ||
                   session.displayName?.lowercased().contains(lower) == true ||
                   session.command.lowercased().contains(lower) ||
                   session.id.uuidString.prefix(8) == targetName.prefix(8)
        }) else {
            return "error: agent '\(targetName)' not found. Use 'omaestri list' to see connected agents."
        }

        // 标记通信中
        if let conn = cm.connections.values.first(where: {
            ($0.nodeIdA == callerTid && $0.nodeIdB == targetSession.id) ||
            ($0.nodeIdA == targetSession.id && $0.nodeIdB == callerTid)
        }) { cm.markCommunicating(conn.id) }

        // 标记目标终端有活跃任务（使任务完成后能触发红点通知）
        targetSession.markActiveTask()

        // 注入 prompt（FR33）
        let injectedPrompt = prompt.hasSuffix("\n") ? prompt : prompt + "\n"
        tm.writeLine(to: targetSession.id, text: injectedPrompt)
        logger.debug("Prompt injected to \(targetSession.id.uuidString.prefix(8)): \(prompt.prefix(50))")

        return await waitForResponse(from: targetSession)
    }

    // MARK: - 响应等待

    @MainActor
    private func waitForResponse(from session: TerminalSession) async -> String {
        let deadline = Date().addingTimeInterval(responseTimeout)
        var lastOutputCount = session.recentOutput().components(separatedBy: "\n").count
        var idleStart: Date? = nil

        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            let currentOutput = session.recentOutput()
            let currentCount = currentOutput.components(separatedBy: "\n").count

            if currentCount > lastOutputCount {
                // 有新输出，重置空闲计时
                lastOutputCount = currentCount
                idleStart = nil
            } else {
                // 输出静止
                if idleStart == nil { idleStart = Date() }
                if let idleStart, Date().timeIntervalSince(idleStart) >= idleThreshold {
                    // 达到空闲阈值，认为响应完成
                    break
                }
            }
        }

        let output = session.recentOutput(lines: 50)
        return output.isEmpty ? "(no response)" : output
    }
}
