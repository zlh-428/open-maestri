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

        // 找到连接 ID，ask 全程保持 communicating 状态，收到回复后再恢复 idle
        let connectionId = cm.connections.values.first(where: {
            ($0.nodeIdA == callerTid && $0.nodeIdB == targetSession.id) ||
            ($0.nodeIdA == targetSession.id && $0.nodeIdB == callerTid)
        })?.id
        if let cid = connectionId {
            cm.updateStatus(.communicating, for: cid)
            NotificationCenter.default.post(name: .connectionStatusChanged, object: nil)
        }

        // 标记目标终端有活跃任务（使任务完成后能触发红点通知）
        targetSession.markActiveTask()

        // 将 prompt 写入目标终端，用 \r 触发 readline 提交（\n 只输入不提交）
        let injectedPrompt = prompt.hasSuffix("\r") ? prompt : prompt.trimmingCharacters(in: .newlines) + "\r"
        tm.write(to: targetSession.id, text: injectedPrompt)
        logger.debug("Prompt injected to \(targetSession.id.uuidString.prefix(8)): \(prompt.prefix(50))")

        // 记录注入前的 buffer 行数，用于过滤注入前的提示符（避免误判）
        let baselineLineCount = bufferLineCount(session: targetSession, in: tm)

        // 等待目标终端执行完成，然后返回其屏幕内容
        let result = await waitForIdleThenSnapshot(session: targetSession, in: tm, baselineLineCount: baselineLineCount)

        // 收到回复后恢复连接线为 idle
        if let cid = connectionId {
            cm.updateStatus(.idle, for: cid)
            NotificationCenter.default.post(name: .connectionStatusChanged, object: nil)
        }
        return result
    }

    // MARK: - 等待回复完成后取屏幕快照

    @MainActor
    private func waitForIdleThenSnapshot(session: TerminalSession, in tm: TerminalManager, baselineLineCount: Int) async -> String {
        // 短暂延迟确保命令已开始执行
        try? await Task.sleep(for: .milliseconds(300))

        let deadline = Date().addingTimeInterval(responseTimeout)

        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(300))
            if hasPromptReturned(session: session, in: tm, baselineLineCount: baselineLineCount) { break }
        }

        return snapshot(session: session, in: tm)
    }

    /// 判断目标终端是否已回到提示符（命令执行完毕）
    /// baselineLineCount：注入前的 buffer 行数，必须有新增行才开始检测，避免误判输入回显中的 ❯
    @MainActor
    private func hasPromptReturned(session: TerminalSession, in tm: TerminalManager, baselineLineCount: Int) -> Bool {
        guard let provider = tm.providers[session.id],
              let termView = provider.terminalView else {
            return session.isIdle
        }

        let data = termView.getTerminal().getBufferAsData()
        guard !data.isEmpty else { return false }

        let text = String(decoding: data, as: UTF8.self)
        var lines = text.components(separatedBy: "\n")

        // 必须有新增行，才说明命令真正开始执行并产生了输出
        // （避免误判：注入后 buffer 行数未增加时，末行的 ❯ 只是输入回显）
        guard lines.count > baselineLineCount + 2 else { return false }

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

    /// 注入前获取 buffer 当前行数（作为 baseline）
    @MainActor
    private func bufferLineCount(session: TerminalSession, in tm: TerminalManager) -> Int {
        guard let provider = tm.providers[session.id],
              let termView = provider.terminalView else { return 0 }
        let data = termView.getTerminal().getBufferAsData()
        guard !data.isEmpty else { return 0 }
        return String(decoding: data, as: UTF8.self).components(separatedBy: "\n").count
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
