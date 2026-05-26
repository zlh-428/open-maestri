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
        let cleaned = stripAnsi(output)
        return cleaned.isEmpty ? "(no recent output)" : cleaned
    }

    private func stripAnsi(_ text: String) -> String {
        // 过滤 CSI 序列（ESC [ ... 最终字节）、OSC 序列、单字符 ESC 序列
        var result = ""
        result.reserveCapacity(text.count)
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch == "\u{1B}" {
                let next = text.index(after: i)
                if next < text.endIndex {
                    let nc = text[next]
                    if nc == "[" {
                        // CSI 序列：跳到参数结束（最终字节 @-~）
                        var j = text.index(after: next)
                        while j < text.endIndex && !(text[j] >= "\u{40}" && text[j] <= "\u{7E}") {
                            j = text.index(after: j)
                        }
                        i = j < text.endIndex ? text.index(after: j) : text.endIndex
                    } else if nc == "]" {
                        // OSC 序列：跳到 BEL 或 ST（ESC \）
                        var j = text.index(after: next)
                        while j < text.endIndex && text[j] != "\u{07}" && text[j] != "\u{1B}" {
                            j = text.index(after: j)
                        }
                        if j < text.endIndex && text[j] == "\u{1B}" {
                            j = text.index(after: j)
                            if j < text.endIndex { j = text.index(after: j) }
                        } else if j < text.endIndex {
                            j = text.index(after: j)
                        }
                        i = j
                    } else {
                        // 其他单字符 ESC 序列
                        i = text.index(after: next)
                    }
                } else {
                    i = text.endIndex
                }
            } else {
                result.append(ch)
                i = text.index(after: i)
            }
        }
        return result
    }

    private func runOnDetached(_ block: @escaping () async -> String) -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var result = ""
        Task.detached { result = await block(); semaphore.signal() }
        semaphore.wait()
        return result
    }
}
