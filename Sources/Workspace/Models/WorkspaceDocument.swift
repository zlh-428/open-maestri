import Foundation

/// workspace.json 顶层容器
/// 与 Maestri v0.25.4 格式完全兼容（schemaVersion: 2）
struct WorkspaceDocument: Codable {
    let payload: WorkspacePayload
    let schemaVersion: Int
    let type: String

    init(payload: WorkspacePayload) {
        self.payload = payload
        self.schemaVersion = Constants.schemaVersion
        self.type = "workspace"
    }
}
