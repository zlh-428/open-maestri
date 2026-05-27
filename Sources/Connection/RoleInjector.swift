import Foundation
import OSLog

/// Role 注入器
/// 在 Terminal 分配 Role 时写入 role.json + CLAUDE.md + AGENTS.md，路径对标 Maestri：
/// {workingDirectory}/.maestri/roles/{roleId}/
final class RoleInjector {
    static let shared = RoleInjector()
    private let logger = Logger.make(category: "RoleInjector")
    private init() {}

    // MARK: - Public API

    /// 准备 Role 目录，返回 terminal 应该启动的目录路径
    @discardableResult
    func prepareRoleDirectory(roleId: UUID, rolePreset: RolePreset, workingDirectory: String) -> String {
        let roleDir = roleDirPath(roleId: roleId, workingDirectory: workingDirectory)
        let instructionContent = buildInstructionContent(rolePrompt: rolePreset.prompt, workingDirectory: workingDirectory)
        do {
            try FileManager.default.createDirectory(atPath: roleDir, withIntermediateDirectories: true)
            try instructionContent.write(toFile: "\(roleDir)/CLAUDE.md", atomically: true, encoding: .utf8)
            try instructionContent.write(toFile: "\(roleDir)/AGENTS.md", atomically: true, encoding: .utf8)
            try writeRoleJson(rolePreset: rolePreset, to: roleDir)
            logger.debug("Role files written to \(roleDir)")
        } catch {
            logger.error("Failed to write role files: \(error)")
        }
        return roleDir
    }

    /// 兼容旧调用签名（prompt-only），不写 role.json（内部使用）
    @discardableResult
    func prepareRoleDirectory(roleId: UUID, rolePrompt: String, workingDirectory: String) -> String {
        let roleDir = roleDirPath(roleId: roleId, workingDirectory: workingDirectory)
        let content = buildInstructionContent(rolePrompt: rolePrompt, workingDirectory: workingDirectory)
        do {
            try FileManager.default.createDirectory(atPath: roleDir, withIntermediateDirectories: true)
            try content.write(toFile: "\(roleDir)/CLAUDE.md", atomically: true, encoding: .utf8)
            try content.write(toFile: "\(roleDir)/AGENTS.md", atomically: true, encoding: .utf8)
            logger.debug("Role instruction files written to \(roleDir)")
        } catch {
            logger.error("Failed to write role instruction files: \(error)")
        }
        return roleDir
    }

    /// 移除 Role 目录（从指定工作区）
    func removeRoleDirectory(roleId: UUID, workingDirectory: String) {
        let roleDir = roleDirPath(roleId: roleId, workingDirectory: workingDirectory)
        try? FileManager.default.removeItem(atPath: roleDir)
        logger.debug("Role dir removed: \(roleDir)")
    }

    /// 旧签名兼容：不知道工作区时从全局路径删（向后兼容，新代码应传 workingDirectory）
    func removeRoleDirectory(roleId: UUID) {
        let globalDir = PersistenceManager.shared.appDataURL
            .appendingPathComponent("roles/\(roleId.uuidString)")
            .path
        try? FileManager.default.removeItem(atPath: globalDir)
    }

    // MARK: - Helpers

    func roleDirPath(roleId: UUID, workingDirectory: String) -> String {
        let base = workingDirectory.isEmpty
            ? PersistenceManager.shared.appDataURL.appendingPathComponent("roles").path
            : (workingDirectory as NSString).appendingPathComponent(".maestri/roles")
        return (base as NSString).appendingPathComponent(roleId.uuidString)
    }

    private func buildInstructionContent(rolePrompt: String, workingDirectory: String) -> String {
        """
        <your_assigned_role>
        \(rolePrompt)
        </your_assigned_role>

        <working_directory>
        IMPORTANT: You were started in this directory to receive the above role assignment. The actual project you should be working on is located at:
        \(workingDirectory)
        </working_directory>
        """
    }

    private func writeRoleJson(rolePreset: RolePreset, to dir: String) throws {
        struct RoleJsonPayload: Encodable {
            let color: String
            let icon: String
            let id: String
            let name: String
            let prompt: String
            let schemaVersion: Int
        }
        let payload = RoleJsonPayload(
            color: rolePreset.color,
            icon: rolePreset.icon,
            id: rolePreset.id.uuidString.uppercased(),
            name: rolePreset.name,
            prompt: rolePreset.prompt,
            schemaVersion: 1
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: URL(fileURLWithPath: "\(dir)/role.json"), options: .atomic)
    }
}
