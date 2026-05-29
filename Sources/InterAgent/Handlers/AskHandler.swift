import Foundation
import OSLog

final class AskHandler {
    static let shared = AskHandler()
    private let logger = Logger.make(category: "AskHandler")
    private let responseTimeout: TimeInterval = 30
    private init() {}

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

        let connectionId = cm.connections.values.first(where: {
            ($0.nodeIdA == callerTid && $0.nodeIdB == targetSession.id) ||
            ($0.nodeIdA == targetSession.id && $0.nodeIdB == callerTid)
        })?.id
        if let cid = connectionId {
            cm.updateStatus(.communicating, for: cid)
            NotificationCenter.default.post(name: .connectionStatusChanged, object: nil)
        }

        targetSession.markActiveTask()

        let injectedPrompt = prompt.hasSuffix("\r") ? prompt : prompt.trimmingCharacters(in: .newlines) + "\r"
        tm.write(to: targetSession.id, text: injectedPrompt)
        logger.debug("Prompt injected to \(targetSession.id.uuidString.prefix(8)): \(prompt.prefix(50))")

        let result: String
        if targetSession.agentType == "generic_shell" {
            let baselineLineCount = bufferLineCount(session: targetSession, in: tm)
            result = await waitForPromptEvent(session: targetSession, in: tm, baselineLineCount: baselineLineCount)
        } else {
            result = await waitForIdleNotification(session: targetSession, in: tm)
        }

        if let cid = connectionId {
            cm.updateStatus(.idle, for: cid)
            NotificationCenter.default.post(name: .connectionStatusChanged, object: nil)
        }
        return result
    }

    // MARK: - Shell 策略：事件驱动提示符检测

    /// 订阅 PTY 输出回调，每次有新输出时检测提示符，匹配即立即返回
    @MainActor
    private func waitForPromptEvent(session: TerminalSession, in tm: TerminalManager, baselineLineCount: Int) async -> String {
        try? await Task.sleep(for: .milliseconds(150))

        return await withCheckedContinuation { continuation in
            let deadline = Date().addingTimeInterval(responseTimeout)
            var resumed = false

            guard let provider = tm.providers[session.id] else {
                continuation.resume(returning: snapshot(session: session, in: tm))
                return
            }

            let previousCallback = provider.onDataReceived

            provider.onDataReceived = { [weak self] text in
                previousCallback?(text)
                guard let self, !resumed else { return }
                Task { @MainActor in
                    guard !resumed else { return }
                    if self.hasPromptReturned(session: session, in: tm, baselineLineCount: baselineLineCount) {
                        resumed = true
                        provider.onDataReceived = previousCallback
                        continuation.resume(returning: self.snapshot(session: session, in: tm))
                    } else if Date() >= deadline {
                        resumed = true
                        provider.onDataReceived = previousCallback
                        continuation.resume(returning: self.snapshot(session: session, in: tm))
                    }
                }
            }

            // 超时保底
            Task { @MainActor in
                let remaining = deadline.timeIntervalSinceNow
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                }
                guard !resumed else { return }
                resumed = true
                provider.onDataReceived = previousCallback
                continuation.resume(returning: self.snapshot(session: session, in: tm))
            }
        }
    }

    // MARK: - Agent 策略：等待 terminalBecameIdle 通知

    /// 监听 .terminalBecameIdle 通知，target 终端空闲后立即返回
    @MainActor
    private func waitForIdleNotification(session: TerminalSession, in tm: TerminalManager) async -> String {
        // 短暂延迟等待 agent 开始处理（避免注入后 activityMonitor 尚未感知到新输出）
        try? await Task.sleep(for: .milliseconds(500))

        return await withCheckedContinuation { continuation in
            var resumed = false
            var observer: NSObjectProtocol?

            let deadline = Date().addingTimeInterval(responseTimeout)

            observer = NotificationCenter.default.addObserver(
                forName: .terminalBecameIdle,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      !resumed,
                      let tid = notification.userInfo?["terminalId"] as? UUID,
                      tid == session.id else { return }
                resumed = true
                if let obs = observer { NotificationCenter.default.removeObserver(obs) }
                Task { @MainActor in
                    continuation.resume(returning: self.snapshot(session: session, in: tm))
                }
            }

            // 超时保底
            Task { @MainActor in
                let remaining = deadline.timeIntervalSinceNow
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                }
                guard !resumed else { return }
                resumed = true
                if let obs = observer { NotificationCenter.default.removeObserver(obs) }
                continuation.resume(returning: self.snapshot(session: session, in: tm))
            }
        }
    }

    // MARK: - 共用工具

    /// 判断目标终端是否已回到提示符（命令执行完毕）
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

        guard lines.count > baselineLineCount + 1 else { return false }

        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        guard let lastLine = lines.last else { return false }
        let trimmed = lastLine.trimmingCharacters(in: .whitespaces)

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
