import Foundation

/// sidebar-layout.json 持久化模型（schemaVersion:2，对标 maestri-tech-analysis.md 第 247 行）
struct SidebarLayout: Codable {
    var schemaVersion: Int = 2
    var topLevelItems: [UUID]   // 工作区 ID 的显示顺序
    var groups: [SidebarGroup]  // 折叠分组

    init() {
        topLevelItems = []
        groups = []
    }
}

struct SidebarGroup: Codable, Identifiable {
    var id: UUID
    var name: String
    var isCollapsed: Bool
    var items: [UUID]   // 工作区 ID

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.isCollapsed = false
        self.items = []
    }
}
