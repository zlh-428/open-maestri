import Foundation

/// 应用统一错误类型
enum MaestriError: LocalizedError {
    case workspaceNotFound(UUID)
    case terminalConnectionFailed(String)
    case skillInjectionFailed(String)
    case persistenceSaveFailed(String)
    case persistenceLoadFailed(String)
    case interAgentServerFailed(String)
    case schemaMigrationFailed(Int, Int)
    case noteReadFailed(String)
    case noteWriteFailed(String)
    case portalCommandFailed(String)
    case sshConnectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .workspaceNotFound(let id):
            return "Workspace not found: \(id)"
        case .terminalConnectionFailed(let msg):
            return "Terminal connection failed: \(msg)"
        case .skillInjectionFailed(let msg):
            return "Skill injection failed: \(msg)"
        case .persistenceSaveFailed(let msg):
            return "Failed to save: \(msg)"
        case .persistenceLoadFailed(let msg):
            return "Failed to load: \(msg)"
        case .interAgentServerFailed(let msg):
            return "InterAgent server error: \(msg)"
        case .schemaMigrationFailed(let from, let to):
            return "Schema migration failed from v\(from) to v\(to)"
        case .noteReadFailed(let msg):
            return "Note read failed: \(msg)"
        case .noteWriteFailed(let msg):
            return "Note write failed: \(msg)"
        case .portalCommandFailed(let msg):
            return "Portal command failed: \(msg)"
        case .sshConnectionFailed(let msg):
            return "SSH connection failed: \(msg)"
        }
    }
}
