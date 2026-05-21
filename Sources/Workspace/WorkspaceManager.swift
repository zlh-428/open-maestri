import Foundation
import Observation
import OSLog

/// 单个工作区的状态管理（Story 1.4 + 1.5）
/// - 节点/连接的运行时状态
/// - workspace.json 读写（通过 PersistenceManager 原子写入）
@Observable
final class WorkspaceManager: Identifiable {
    let id: UUID
    var name: String
    var workingDirectory: String

    // 运行时状态（与 WorkspacePayload 同步）
    var nodes: [CanvasNode] = []
    var connections: [TerminalConnection] = []
    var noteConnections: [NoteConnection] = []
    var portalConnections: [PortalConnection] = []
    var portalToPortalConnections: [PortalToPortalConnection] = []
    var noteToNoteConnections: [NoteToNoteConnection] = []
    var crossFloorConnections: [CrossFloorConnection] = []
    var floors: [FloorEntry] = []
    var drawings: [Drawing] = []
    var canvasOrigin: CGPoint = Constants.canvasInitialOrigin
    var canvasZoom: CGFloat = 1.0

    /// 该工作区未读的"任务完成"通知数（终端从 active→idle 时累积，用户切回时清零）
    var unreadActivityCount: Int = 0

    /// 脏标记：有未持久化的修改时为 true（autosave 时仅保存 dirty 的工作区）
    var isDirty: Bool = false

    /// Terminal 节点数量（侧边栏徽章用，避免在 View body 里做 O(n) filter）
    var terminalCount: Int {
        nodes.count(where: { if case .terminal = $0.content { true } else { false } })
    }

    private let logger = Logger.make(category: "WorkspaceManager")
    private let pm = PersistenceManager.shared

    init(entry: WorkspaceEntry) {
        self.id = entry.id
        self.name = entry.name
        self.workingDirectory = entry.workingDirectory
    }

    init(id: UUID = UUID(), name: String, workingDirectory: String) {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
    }

    // MARK: - 加载（Story 1.3 AC：重启后恢复布局 < 0.5s，NFR2）

    func load() throws {
        let doc = try pm.loadWorkspace(id: id)
        let payload = doc.payload
        nodes = payload.nodes
        connections = payload.connections
        noteConnections = payload.noteConnections
        portalConnections = payload.portalConnections
        portalToPortalConnections = payload.portalToPortalConnections
        noteToNoteConnections = payload.noteToNoteConnections
        crossFloorConnections = payload.crossFloorConnections
        floors = payload.floors
        drawings = payload.drawings
        canvasOrigin = payload.canvasOrigin
        canvasZoom = payload.canvasZoom
        logger.debug("Workspace \(self.id) loaded: \(self.nodes.count) nodes")
    }

    // MARK: - 保存（Story 1.5 AC：autosave 后台执行）

    func save() async throws {
        let payload = buildPayload()
        let doc = WorkspaceDocument(payload: payload)
        try await pm.saveWorkspace(doc)
        isDirty = false
        logger.debug("Workspace \(self.id) saved")
    }

    func saveSync() throws {
        let payload = buildPayload()
        let doc = WorkspaceDocument(payload: payload)
        let url = pm.workspaceURL(id: id)
        try pm.saveSync(doc, to: url)
    }

    // MARK: - 节点管理

    func addNode(_ node: CanvasNode) {
        nodes.append(node)
        isDirty = true
    }

    func removeNode(id nodeId: UUID) {
        // 停止 Terminal PTY 进程（避免内存泄漏）
        if let node = nodes.first(where: { $0.id == nodeId }),
           case .terminal = node.content {
            Task { @MainActor in
                TerminalManager.shared.removeTerminal(id: nodeId)
                TerminalProviderRegistry.shared.unregister(terminalId: nodeId)
            }
        }
        nodes.removeAll { $0.id == nodeId }
        isDirty = true
        connections.removeAll { $0.terminalIdA == nodeId || $0.terminalIdB == nodeId }
        noteConnections.removeAll { $0.terminalId == nodeId || $0.noteNodeId == nodeId }
        portalConnections.removeAll { $0.terminalId == nodeId || $0.portalNodeId == nodeId }
    }

    func updateNodeFrame(id nodeId: UUID, frame: CGRect) {
        if let idx = nodes.firstIndex(where: { $0.id == nodeId }) {
            nodes[idx].frame = frame
            nodes[idx].lastModifiedAt = Date()
            isDirty = true
        }
    }

    // MARK: - 连接持久化

    func addConnection(_ conn: TerminalConnection) {
        connections.removeAll { $0.id == conn.id }
        connections.append(conn)
        isDirty = true
    }

    func addNoteConnection(_ conn: NoteConnection) {
        noteConnections.removeAll { $0.id == conn.id }
        noteConnections.append(conn)
        isDirty = true
    }

    func addPortalConnection(_ conn: PortalConnection) {
        portalConnections.removeAll { $0.id == conn.id }
        portalConnections.append(conn)
        isDirty = true
    }

    func addPortalToPortalConnection(_ conn: PortalToPortalConnection) {
        portalToPortalConnections.removeAll { $0.id == conn.id }
        portalToPortalConnections.append(conn)
    }

    func removeConnection(id connId: UUID) {
        connections.removeAll { $0.id == connId }
        noteConnections.removeAll { $0.id == connId }
        portalConnections.removeAll { $0.id == connId }
        portalToPortalConnections.removeAll { $0.id == connId }
        isDirty = true
    }

    // MARK: - 私有辅助

    /// 将当前状态快照为纯值类型，可安全传递到后台线程
    func snapshotPayload() -> WorkspacePayload { buildPayload() }

    private func buildPayload() -> WorkspacePayload {
        var payload = WorkspacePayload(id: id, name: name, workingDirectory: workingDirectory)
        payload.nodes = nodes
        payload.connections = connections
        payload.noteConnections = noteConnections
        payload.portalConnections = portalConnections
        payload.portalToPortalConnections = portalToPortalConnections
        payload.noteToNoteConnections = noteToNoteConnections
        payload.crossFloorConnections = crossFloorConnections
        payload.floors = floors
        payload.drawings = drawings
        payload.canvasOrigin = canvasOrigin
        payload.canvasZoom = canvasZoom
        payload.lastModifiedAt = Date()
        return payload
    }
}
