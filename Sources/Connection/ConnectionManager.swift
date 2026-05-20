import Foundation
import OSLog

/// 连接类型
enum ConnectionType {
    case terminalToTerminal
    case terminalToNote
    case terminalToPortal
    case portalToPortal
    case noteToNote
}

/// 连接状态
enum ConnectionStatus {
    case idle           // 灰色虚线
    case communicating  // 绿色 glow
    case disconnected   // 红色虚线
    case error          // 错误
}

/// 运行时连接记录（内存中，序列化版本在 WorkspacePayload）
struct ActiveConnection {
    let id: UUID
    let nodeIdA: UUID
    let nodeIdB: UUID
    let type: ConnectionType
    var status: ConnectionStatus = .idle
}

/// 连接生命周期管理器（@MainActor，画布状态修改必须在主线程）
@MainActor
final class ConnectionManager {
    static let shared = ConnectionManager()
    private let logger = Logger.make(category: "ConnectionManager")

    private(set) var connections: [UUID: ActiveConnection] = [:]

    private init() {}

    // MARK: - 建立连接

    /// 建立 Terminal↔Terminal 连接，自动注入 Skill
    func connectTerminals(
        idA: UUID, idB: UUID,
        serverPort: UInt16,
        ropePoints: [[Double]] = []
    ) -> TerminalConnection {
        let conn = TerminalConnection(
            id: UUID(),
            terminalIdA: idA,
            terminalIdB: idB,
            ropePoints: ropePoints.isEmpty
                ? buildDefaultRopePoints() : ropePoints
        )
        let active = ActiveConnection(id: conn.id, nodeIdA: idA, nodeIdB: idB, type: .terminalToTerminal)
        connections[conn.id] = active

        // 向双端注入 Skill（FR29）
        let host = "\(Constants.interAgentServerHost):\(serverPort)"
        SkillInjector.shared.inject(to: idA, host: host)
        SkillInjector.shared.inject(to: idB, host: host)

        logger.info("Terminal connection established: \(idA.uuidString.prefix(8)) ↔ \(idB.uuidString.prefix(8))")
        return conn
    }

    /// 建立 Terminal↔Terminal 连接（同时持久化到 workspace）
    func connectTerminals(
        idA: UUID, idB: UUID,
        serverPort: UInt16,
        ropePoints: [[Double]] = [],
        workspace: WorkspaceManager?
    ) -> TerminalConnection {
        let conn = connectTerminals(idA: idA, idB: idB, serverPort: serverPort, ropePoints: ropePoints)
        workspace?.addConnection(conn)
        return conn
    }

    /// 建立 Terminal↔Note 连接（同时持久化到 workspace）
    func connectTerminalToNote(
        terminalId: UUID, noteNodeId: UUID,
        ropePoints: [[Double]] = [],
        workspace: WorkspaceManager?
    ) -> NoteConnection {
        let conn = connectTerminalToNote(terminalId: terminalId, noteNodeId: noteNodeId, ropePoints: ropePoints)
        workspace?.addNoteConnection(conn)
        return conn
    }

    /// 建立 Terminal↔Portal 连接（同时持久化到 workspace）
    func connectTerminalToPortal(
        terminalId: UUID, portalNodeId: UUID,
        ropePoints: [[Double]] = [],
        workspace: WorkspaceManager?
    ) -> PortalConnection {
        let conn = connectTerminalToPortal(terminalId: terminalId, portalNodeId: portalNodeId, ropePoints: ropePoints)
        workspace?.addPortalConnection(conn)
        return conn
    }

    /// 建立 Terminal↔Note 连接
    func connectTerminalToNote(terminalId: UUID, noteNodeId: UUID, ropePoints: [[Double]] = []) -> NoteConnection {
        let conn = NoteConnection(
            id: UUID(), terminalId: terminalId, noteNodeId: noteNodeId,
            ropePoints: ropePoints.isEmpty ? buildDefaultRopePoints() : ropePoints
        )
        let active = ActiveConnection(id: conn.id, nodeIdA: terminalId, nodeIdB: noteNodeId, type: .terminalToNote)
        connections[conn.id] = active
        logger.info("Terminal↔Note connection: \(terminalId.uuidString.prefix(8)) → \(noteNodeId.uuidString.prefix(8))")
        return conn
    }

    /// 建立 Terminal↔Portal 连接
    func connectTerminalToPortal(terminalId: UUID, portalNodeId: UUID, ropePoints: [[Double]] = []) -> PortalConnection {
        let conn = PortalConnection(
            id: UUID(), terminalId: terminalId, portalNodeId: portalNodeId,
            ropePoints: ropePoints.isEmpty ? buildDefaultRopePoints() : ropePoints
        )
        let active = ActiveConnection(id: conn.id, nodeIdA: terminalId, nodeIdB: portalNodeId, type: .terminalToPortal)
        connections[conn.id] = active
        return conn
    }

    /// 建立 Note↔Note 连接（Note Chaining）
    func connectNoteToNote(noteNodeIdA: UUID, noteNodeIdB: UUID, ropePoints: [[Double]] = []) -> NoteToNoteConnection {
        let conn = NoteToNoteConnection(
            noteNodeIdA: noteNodeIdA, noteNodeIdB: noteNodeIdB,
            ropePoints: ropePoints.isEmpty ? buildDefaultRopePoints() : ropePoints
        )
        let active = ActiveConnection(id: conn.id, nodeIdA: noteNodeIdA, nodeIdB: noteNodeIdB, type: .noteToNote)
        connections[conn.id] = active
        logger.info("Note↔Note connection: \(noteNodeIdA.uuidString.prefix(8)) ↔ \(noteNodeIdB.uuidString.prefix(8))")
        return conn
    }

    /// 建立 Portal↔Portal 连接（共享 session）
    func connectPortalToPortal(portalIdA: UUID, portalIdB: UUID, ropePoints: [[Double]] = []) -> PortalToPortalConnection {
        let conn = PortalToPortalConnection(
            portalIdA: portalIdA, portalIdB: portalIdB,
            ropePoints: ropePoints.isEmpty ? buildDefaultRopePoints() : ropePoints
        )
        let active = ActiveConnection(id: conn.id, nodeIdA: portalIdA, nodeIdB: portalIdB, type: .portalToPortal)
        connections[conn.id] = active
        logger.info("Portal↔Portal connection: \(portalIdA.uuidString.prefix(8)) ↔ \(portalIdB.uuidString.prefix(8))")
        return conn
    }

    // MARK: - 断开连接

    func disconnect(id: UUID) {
        connections.removeValue(forKey: id)
        logger.debug("Connection \(id.uuidString.prefix(8)) removed")
    }

    func disconnectAll(involvedNode nodeId: UUID) {
        let toRemove = connections.values.filter { $0.nodeIdA == nodeId || $0.nodeIdB == nodeId }
        toRemove.forEach { connections.removeValue(forKey: $0.id) }
    }

    // MARK: - 状态更新

    func updateStatus(_ status: ConnectionStatus, for connectionId: UUID) {
        connections[connectionId]?.status = status
    }

    func markCommunicating(_ connectionId: UUID) {
        updateStatus(.communicating, for: connectionId)
        // 150ms 后恢复 idle（FR: 通信结束后渐变回灰色）
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            if connections[connectionId]?.status == .communicating {
                updateStatus(.idle, for: connectionId)
            }
        }
    }

    // MARK: - 查询

    func connections(for nodeId: UUID) -> [ActiveConnection] {
        connections.values.filter { $0.nodeIdA == nodeId || $0.nodeIdB == nodeId }
    }

    func connectedNodeIds(for nodeId: UUID) -> [UUID] {
        connections(for: nodeId).map { $0.nodeIdA == nodeId ? $0.nodeIdB : $0.nodeIdA }
    }

    // MARK: - 工具

    private func buildDefaultRopePoints() -> [[Double]] {
        Array(repeating: [0.0, 0.0], count: Constants.ropeControlPointCount)
    }
}
