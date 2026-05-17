import Foundation
import OSLog

final class ListHandler {
    static let shared = ListHandler()
    private let logger = Logger.make(category: "ListHandler")
    private init() {}

    func handle(args: [String], terminalId: UUID?) -> String {
        guard let tid = terminalId else { return "error: missing terminal ID" }
        return runOnMain { await self.handleAsync(args: args, terminalId: tid) }
    }

    @MainActor
    func handleAsync(args: [String], terminalId: UUID?) async -> String {
        guard let tid = terminalId else { return "error: missing terminal ID" }
        let cm = ConnectionManager.shared
        let tm = TerminalManager.shared

        var lines: [String] = []

        // 自身信息（显示 agentName 或 command，以及 roleName）
        if let self_ = tm.terminals[tid] {
            let name = self_.agentName ?? (self_.command.isEmpty ? "Shell" : self_.command)
            let roleStr = self_.roleName.map { " (role: \($0))" } ?? ""
            lines.append("You: \(name)\(roleStr)")
        }

        // 按类型分组连接
        var agents:  [String] = []
        var notes:   [String] = []
        var portals: [String] = []

        for conn in cm.connections(for: tid) {
            let otherId = conn.nodeIdA == tid ? conn.nodeIdB : conn.nodeIdA
            switch conn.type {
            case .terminalToTerminal:
                if let session = tm.terminals[otherId] {
                    let roleStr = session.roleName.map { " (role: \($0))" } ?? ""
                    let cmd = session.command.isEmpty ? "Shell" : session.command
                    agents.append("  - \(cmd)\(roleStr) [\(otherId.uuidString.prefix(8))]")
                } else {
                    agents.append("  - unknown [\(otherId.uuidString.prefix(8))]")
                }
            case .terminalToNote:
                let noteName = resolveNoteName(nodeId: otherId)
                notes.append("  - \(noteName) [\(otherId.uuidString.prefix(8))]")
            case .terminalToPortal:
                let portalName = resolvePortalName(nodeId: otherId)
                portals.append("  - \(portalName) [\(otherId.uuidString.prefix(8))]")
            default:
                break
            }
        }

        if agents.isEmpty && notes.isEmpty && portals.isEmpty {
            return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n") + "No connections."
        }

        if !agents.isEmpty {
            lines.append("Agents:")
            lines.append(contentsOf: agents)
        }
        if !notes.isEmpty {
            lines.append("Notes:")
            lines.append(contentsOf: notes)
        }
        if !portals.isEmpty {
            lines.append("Portals:")
            lines.append(contentsOf: portals)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - 名称解析

    @MainActor
    private func resolveNoteName(nodeId: UUID) -> String {
        NoteRegistry.shared.name(forNodeId: nodeId) ?? "Note"
    }

    @MainActor
    private func resolvePortalName(nodeId: UUID) -> String {
        "Portal"
    }

    private func runOnMain(_ block: @escaping () async -> String) -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var result = ""
        Task.detached { result = await block(); semaphore.signal() }
        semaphore.wait()
        return result
    }
}
