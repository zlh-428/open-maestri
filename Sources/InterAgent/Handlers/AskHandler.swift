import Foundation
import OSLog

final class AskHandler {
    static let shared = AskHandler()
    private let logger = Logger.make(category: "AskHandler")
    private let responseTimeout: TimeInterval = 30
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
        // 匹配优先级：agentName（Maestro 招募设置）> displayName > command 名称 > UUID 前缀
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

        // 将 prompt 写入目标终端，用 \r 触发 readline 提交（\n 只输入不提交）
        let injectedPrompt = prompt.hasSuffix("\r") ? prompt : prompt.trimmingCharacters(in: .newlines) + "\r"
        tm.write(to: targetSession.id, text: injectedPrompt)
        logger.debug("Prompt injected to \(targetSession.id.uuidString.prefix(8)): \(prompt.prefix(50))")

        // 等待目标终端执行完成，然后返回其屏幕内容
        return await waitForIdleThenSnapshot(session: targetSession, in: tm)
    }

    // MARK: - 等待回复完成后取屏幕快照

    @MainActor
    private func waitForIdleThenSnapshot(session: TerminalSession, in tm: TerminalManager) async -> String {
        // 短暂延迟确保命令已开始执行
        try? await Task.sleep(for: .milliseconds(300))

        let deadline = Date().addingTimeInterval(responseTimeout)
        let injectedAt = Date()

        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(300))
            // 检测提示符是否重新出现（shell 提示符 / Claude Code ❯ 提示符）
            // 这比 isIdle 更可靠：spinner 动画会持续刷新 PTY 输出导致 isIdle 永远不翻转
            if hasPromptReturned(session: session, injectedAt: injectedAt, in: tm) { break }
        }

        return snapshot(session: session, in: tm)
    }

    /// 判断目标终端的提示符是否已在注入时间点之后重新出现
    @MainActor
    private func hasPromptReturned(session: TerminalSession, injectedAt: Date, in tm: TerminalManager) -> Bool {
        // 至少等注入后 500ms 再开始检测，避免误判注入前的提示符
        guard Date().timeIntervalSince(injectedAt) > 0.5 else { return false }

        guard let provider = tm.providers[session.id],
              let termView = provider.terminalView else {
            // 没有 provider 时 fallback：用 isIdle
            return session.isIdle
        }

        let data = termView.getTerminal().getBufferAsData()
        guard !data.isEmpty else { return false }

        let text = String(decoding: data, as: UTF8.self)
        var lines = text.components(separatedBy: "\n")
        // 去掉尾部空行，找最后一个非空行
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        guard let lastLine = lines.last else { return false }
        let trimmed = lastLine.trimmingCharacters(in: .whitespaces)

        // 匹配常见 shell 提示符尾部：% / $ / > / ❯（zsh/bash/fish/Claude Code）
        return trimmed.hasSuffix("%") || trimmed.hasSuffix("$") ||
               trimmed.hasSuffix(">") || trimmed.hasSuffix("❯") ||
               trimmed.hasSuffix("% ") || trimmed.hasSuffix("$ ")
    }

    /// 从 SwiftTerm buffer 取纯文本快照
    @MainActor
    private func snapshot(session: TerminalSession, in tm: TerminalManager) -> String {
        guard let provider = tm.providers[session.id],
              let termView = provider.terminalView else {
            return session.recentOutput(lines: 50)
        }
        let data = termView.getTerminal().getBufferAsData()
        guard !data.isEmpty else { return session.recentOutput(lines: 50) }

        let fullText = String(decoding: data, as: UTF8.self)
        var lines = fullText.components(separatedBy: "\n")
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
