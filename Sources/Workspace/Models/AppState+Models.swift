import Foundation

/// app-state.json 持久化数据（schemaVersion:1，type:"appState"）
struct AppStateData: Codable {
    var schemaVersion: Int
    var type: String
    var activeWorkspaceId: UUID?
    var hasCompletedOnboarding: Bool
    var hasSeenFloorOnboarding: Bool
    var cleanShutdown: Bool
    var lastOpenedAt: Date?
    var recentWorkspaceIds: [UUID]

    init() {
        self.schemaVersion = 1
        self.type = "appState"
        self.activeWorkspaceId = nil
        self.hasCompletedOnboarding = false
        self.hasSeenFloorOnboarding = false
        self.cleanShutdown = true
        self.lastOpenedAt = nil
        self.recentWorkspaceIds = []
    }
}

/// manifest.json 顶层格式（type 值为 "appState"，沿用 Maestri 原始设计）
struct WorkspaceManifest: Codable {
    var schemaVersion: Int
    var type: String
    var app: String
    var appVersion: String
    var dataFormat: Int
    var workspaces: [WorkspaceEntry]
    var files: [String: String]     // 保留扩展字段

    init() {
        self.schemaVersion = 1
        self.type = "appState"
        self.app = "open-maestri"
        self.appVersion = "1.0.0"
        self.dataFormat = 2
        self.workspaces = []
        self.files = [:]
    }
}

/// 工作区清单条目
struct WorkspaceEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var workingDirectory: String
    var icon: String
    var isPinned: Bool
    var locationType: String        // "local" | "ssh"
    var createdAt: Date
    var lastOpenedAt: Date?

    init(id: UUID = UUID(), name: String, workingDirectory: String, icon: String = "folder") {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
        self.icon = icon
        self.isPinned = false
        self.locationType = "local"
        self.createdAt = Date()
        self.lastOpenedAt = nil
    }
}
