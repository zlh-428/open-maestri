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

/// 工作区颜色选项
enum WorkspaceColor: String, Codable, CaseIterable {
    case blue, red, green, orange, purple, pink, cyan, yellow, rainbow
}

/// 工作区清单条目
struct WorkspaceEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var workingDirectory: String
    var icon: String
    var color: String               // 工作区颜色标识，如 "blue", "red", "green" 等
    var isPinned: Bool
    var locationType: String        // "local" | "ssh"
    var createdAt: Date
    var lastOpenedAt: Date?

    init(id: UUID = UUID(), name: String, workingDirectory: String, icon: String = "folder", color: String = "blue") {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
        self.icon = icon
        self.color = color
        self.isPinned = false
        self.locationType = "local"
        self.createdAt = Date()
        self.lastOpenedAt = nil
    }

    // 向后兼容：旧 JSON 可能没有 color 字段
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        workingDirectory = try container.decode(String.self, forKey: .workingDirectory)
        icon = try container.decode(String.self, forKey: .icon)
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "blue"
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        locationType = try container.decode(String.self, forKey: .locationType)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
    }
}
