import Foundation
import OSLog

/// CLI 命令路由器：根据 args[0] 分发到对应 Handler
final class CLIRouter {
    static let shared = CLIRouter()
    private let logger = Logger.make(category: "CLIRouter")
    private init() {}

    /// 同步路由（供 InterAgentServer HTTP 处理器在后台线程调用）
    func route(args: [String], terminalId: UUID?) -> String {
        guard let command = args.first else { return "error: empty command" }
        switch command {
        case "list", "ask", "check", "recruit", "dismiss", "connect", "role", "portal", "preset":
            return routeAsync(args: args, terminalId: terminalId)
        case "note":
            return NoteHandler.shared.handle(args: args, terminalId: terminalId)
        case "debug":
            return buildDebugInfo(terminalId: terminalId)
        default:
            return "error: unknown command '\(command)'. Try 'omaestri list' for available commands."
        }
    }

    /// 异步路由（semaphore 等待 @MainActor 完成，带超时防止退出时死锁）
    func routeAsync(args: [String], terminalId: UUID?) -> String {
        guard let command = args.first else { return "error: empty command" }
        let semaphore = DispatchSemaphore(value: 0)
        var result = ""
        Task.detached {
            switch command {
            case "list":
                result = await ListHandler.shared.handleAsync(args: args, terminalId: terminalId)
            case "ask":
                result = await AskHandler.shared.handleAsync(args: args, terminalId: terminalId)
            case "check":
                result = await CheckHandler.shared.handleAsync(args: args, terminalId: terminalId)
            case "recruit", "dismiss", "connect", "role", "preset":
                result = await MaestroHandlers.shared.handleAsync(args: args, terminalId: terminalId)
            case "portal":
                result = await PortalHandler.shared.handleAsync(args: args, terminalId: terminalId)
            default:
                result = "error: unknown command '\(command)'"
            }
            semaphore.signal()
        }
        // 超时 300s（5分钟）：给长时间命令（如 ask agent）足够执行时间
        // 仍保留超时以防止退出时 @MainActor 不可达导致永久挂起
        let waitResult = semaphore.wait(timeout: .now() + 300.0)
        if waitResult == .timedOut {
            logger.warning("CLIRouter.routeAsync timed out for command: \(command)")
            return "error: command timed out"
        }
        return result
    }

    /// 纯异步路由（测试和直接 async 调用使用）
    func routeAsync(args: [String], terminalId: UUID?) async -> String {
        guard let command = args.first else { return "error: empty command" }
        switch command {
        case "list":
            return await ListHandler.shared.handleAsync(args: args, terminalId: terminalId)
        case "ask":
            return await AskHandler.shared.handleAsync(args: args, terminalId: terminalId)
        case "check":
            return await CheckHandler.shared.handleAsync(args: args, terminalId: terminalId)
        case "note":
            return await NoteHandler.shared.handleAsync(args: args, terminalId: terminalId)
        case "portal":
            return await PortalHandler.shared.handleAsync(args: args, terminalId: terminalId)
        case "recruit", "dismiss", "connect", "role", "preset":
            return await MaestroHandlers.shared.handleAsync(args: args, terminalId: terminalId)
        case "debug":
            return buildDebugInfo(terminalId: terminalId)
        default:
            return "error: unknown command '\(command)'. Try 'omaestri list' for available commands."
        }
    }

    // MARK: - debug

    private func buildDebugInfo(terminalId: UUID?) -> String {
        let port = InterAgentServer.shared.port
        let tidStr = terminalId?.uuidString ?? "(none)"
        let commands = "list ask check note portal recruit dismiss connect role preset debug"
        return "open-maestri inter-agent server debug:\n  Server port: \(port)\n  Terminal ID: \(tidStr)\n  Commands: \(commands)"
    }
}
