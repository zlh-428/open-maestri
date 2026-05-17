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

    /// 异步路由（semaphore 等待 @MainActor 完成）
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
        semaphore.wait()
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
            return NoteHandler.shared.handle(args: args, terminalId: terminalId)
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
        var lines = ["open-maestri inter-agent server debug:"]
        lines.append("  Server port: \(InterAgentServer.shared.port)")
        if let tid = terminalId {
            lines.append("  Terminal ID: \(tid.uuidString)")
        } else {
            lines.append("  Terminal ID: unknown (missing X-Terminal-ID header)")
        }
        lines.append("  Commands: list ask check note portal recruit dismiss connect role preset debug")
        return lines.joined(separator: "\n")
    }
}
