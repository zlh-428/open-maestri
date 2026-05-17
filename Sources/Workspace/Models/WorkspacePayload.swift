import Foundation
import CoreGraphics

/// 工作区数据载体，所有字段与 Maestri camelCase 格式完全一致（schemaVersion:2）
struct WorkspacePayload: Codable {
    var id: UUID
    var name: String
    var icon: String
    var isPinned: Bool
    var locationType: String        // "local" | "ssh"
    var workingDirectory: String
    var preferredIDE: String        // "cursor" | "vscode" | "xcode"
    var syncConfigFiles: Bool

    var canvasOrigin: CGPoint
    var canvasZoom: CGFloat

    var nodes: [CanvasNode]
    var connections: [TerminalConnection]
    var noteConnections: [NoteConnection]
    var portalConnections: [PortalConnection]
    var portalToPortalConnections: [PortalToPortalConnection]
    var noteToNoteConnections: [NoteToNoteConnection]
    var crossFloorConnections: [CrossFloorConnection]
    var floors: [FloorEntry]
    var drawings: [Drawing]

    var createdAt: Date
    var lastOpenedAt: Date?
    var lastModifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        workingDirectory: String
    ) {
        self.id = id
        self.name = name
        self.icon = "folder"
        self.isPinned = false
        self.locationType = "local"
        self.workingDirectory = workingDirectory
        self.preferredIDE = "cursor"
        self.syncConfigFiles = false
        self.canvasOrigin = Constants.canvasInitialOrigin
        self.canvasZoom = 1.0
        self.nodes = []
        self.connections = []
        self.noteConnections = []
        self.portalConnections = []
        self.portalToPortalConnections = []
        self.noteToNoteConnections = []
        self.crossFloorConnections = []
        self.floors = []
        self.drawings = []
        self.createdAt = Date()
        self.lastOpenedAt = nil
        self.lastModifiedAt = Date()
    }
}

// MARK: - Connection Types

/// Terminal↔Terminal 连接
struct TerminalConnection: Codable, Identifiable {
    var id: UUID
    var createdAt: Date
    var terminalIdA: UUID
    var terminalIdB: UUID
    var ropePoints: [[Double]]  // 21 个控制点 [[x,y], ...]

    init(id: UUID = UUID(), terminalIdA: UUID, terminalIdB: UUID, ropePoints: [[Double]] = []) {
        self.id = id
        self.createdAt = Date()
        self.terminalIdA = terminalIdA
        self.terminalIdB = terminalIdB
        self.ropePoints = ropePoints
    }
}

/// Terminal↔Note 连接
struct NoteConnection: Codable, Identifiable {
    var id: UUID
    var createdAt: Date
    var terminalId: UUID
    var noteNodeId: UUID
    var ropePoints: [[Double]]

    init(id: UUID = UUID(), terminalId: UUID, noteNodeId: UUID, ropePoints: [[Double]] = []) {
        self.id = id
        self.createdAt = Date()
        self.terminalId = terminalId
        self.noteNodeId = noteNodeId
        self.ropePoints = ropePoints
    }
}

/// Terminal↔Portal 连接
struct PortalConnection: Codable, Identifiable {
    var id: UUID
    var createdAt: Date
    var terminalId: UUID
    var portalNodeId: UUID
    var ropePoints: [[Double]]

    init(id: UUID = UUID(), terminalId: UUID, portalNodeId: UUID, ropePoints: [[Double]] = []) {
        self.id = id
        self.createdAt = Date()
        self.terminalId = terminalId
        self.portalNodeId = portalNodeId
        self.ropePoints = ropePoints
    }
}

/// Portal↔Portal 连接（共享 storage session）
struct PortalToPortalConnection: Codable, Identifiable {
    var id: UUID
    var createdAt: Date
    var portalIdA: UUID
    var portalIdB: UUID
    var ropePoints: [[Double]]

    init(id: UUID = UUID(), portalIdA: UUID, portalIdB: UUID, ropePoints: [[Double]] = []) {
        self.id = id
        self.createdAt = Date()
        self.portalIdA = portalIdA
        self.portalIdB = portalIdB
        self.ropePoints = ropePoints
    }
}

/// Note↔Note 连接（Note Chaining）
struct NoteToNoteConnection: Codable, Identifiable {
    var id: UUID
    var createdAt: Date
    var noteNodeIdA: UUID
    var noteNodeIdB: UUID
    var ropePoints: [[Double]]

    init(id: UUID = UUID(), noteNodeIdA: UUID, noteNodeIdB: UUID, ropePoints: [[Double]] = []) {
        self.id = id
        self.createdAt = Date()
        self.noteNodeIdA = noteNodeIdA
        self.noteNodeIdB = noteNodeIdB
        self.ropePoints = ropePoints
    }
}

/// 跨 Floor 连接
struct CrossFloorConnection: Codable, Identifiable {
    var id: UUID
    var createdAt: Date
    var nodeIdA: UUID
    var floorIdA: UUID?         // nil = Ground
    var nodeIdB: UUID
    var floorIdB: UUID?         // nil = Ground
    var ropePoints: [[Double]]
}

/// Floor 条目（workspace.json 中的 floor 引用）
struct FloorEntry: Codable, Identifiable {
    var id: UUID
    var name: String
    var branchName: String
    var worktreePath: String
    var hooks: FloorHooks
    var createdAt: Date
}

/// 画布手绘（drawings），Maestri 支持基础手绘
struct Drawing: Codable, Identifiable {
    var id: UUID
    var points: [[Double]]      // [[x,y], ...]
    var color: String
    var lineWidth: Double
    var createdAt: Date
}
