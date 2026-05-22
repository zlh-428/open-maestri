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

        var sections: [String] = []

        // "You:" 段：当前终端自身名称
        if let selfSession = tm.terminals[tid] {
            let selfName = selfSession.agentName ?? selfSession.displayName ?? (selfSession.command.isEmpty ? "Shell" : selfSession.command)
            sections.append("You:\n  - name: \"\(selfName)\"")
        }

        // 按类型分组连接（对标 Maestri 输出格式）
        var agents:  [String] = []
        var notes:   [String] = []
        var portals: [String] = []

        for conn in cm.connections(for: tid) {
            let otherId = conn.nodeIdA == tid ? conn.nodeIdB : conn.nodeIdA
            switch conn.type {
            case .terminalToTerminal:
                if let session = tm.terminals[otherId] {
                    let name = session.agentName ?? session.displayName ?? (session.command.isEmpty ? "Shell" : session.command)
                    agents.append("  - name: \"\(name)\"")
                } else {
                    agents.append("  - name: \"unknown\"")
                }
            case .terminalToNote:
                let noteName = resolveNoteName(nodeId: otherId)
                notes.append("  - name: \"\(noteName)\"")
            case .terminalToPortal:
                let (portalName, portalURL) = resolvePortalInfo(nodeId: otherId)
                if let url = portalURL {
                    portals.append("  - name: \"\(portalName)\" - url: \(url)")
                } else {
                    portals.append("  - name: \"\(portalName)\"")
                }
            default:
                break
            }
        }

        if agents.isEmpty && notes.isEmpty && portals.isEmpty {
            return sections.isEmpty ? "No connections." : sections.joined(separator: "\n\n") + "\n\nNo connections."
        }

        if !agents.isEmpty {
            sections.append("Connected agents:\n" + agents.joined(separator: "\n"))
        }
        if !portals.isEmpty {
            sections.append("Connected portals (use `omaestri portal snapshot`):\n" + portals.joined(separator: "\n"))
        }
        if !notes.isEmpty {
            sections.append("Connected notes (use `omaestri note read/write/edit`):\n" + notes.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - 名称解析

    @MainActor
    private func resolveNoteName(nodeId: UUID) -> String {
        NoteRegistry.shared.name(forNodeId: nodeId) ?? "Note"
    }

    @MainActor
    private func resolvePortalInfo(nodeId: UUID) -> (name: String, url: String?) {
        if let wv = PortalWebViewStore.shared.webView(for: nodeId) {
            let name = wv.title ?? "Portal"
            let url = wv.url?.absoluteString
            return (name.isEmpty ? "Portal" : name, url)
        }
        return ("Portal", nil)
    }

    private func runOnMain(_ block: @escaping () async -> String) -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var result = ""
        Task.detached { result = await block(); semaphore.signal() }
        semaphore.wait()
        return result
    }
}
