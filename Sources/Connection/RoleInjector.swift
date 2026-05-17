import Foundation
import OSLog

/// Role 注入器
/// 在 Terminal 分配 Role 时写入 CLAUDE.md / AGENTS.md 并返回启动目录
/// 格式与 Maestri 官方完全一致
final class RoleInjector {
    static let shared = RoleInjector()
    private let logger = Logger.make(category: "RoleInjector")
    private init() {}

    /// 准备 Role 目录，返回 terminal 应该启动的目录路径
    /// - Parameters:
    ///   - roleId: 角色 UUID
    ///   - rolePrompt: 角色提示词
    ///   - workingDirectory: 实际项目目录
    /// - Returns: role 子目录路径（terminal 在此目录启动，agent 读取 CLAUDE.md 后得知真实工作目录）
    @discardableResult
    func prepareRoleDirectory(roleId: UUID, rolePrompt: String, workingDirectory: String) -> String {
        let roleDir = PersistenceManager.shared.appDataURL
            .appendingPathComponent("roles/\(roleId.uuidString)")
            .path
        let content = buildRoleFileContent(rolePrompt: rolePrompt, workingDirectory: workingDirectory)
        do {
            try FileManager.default.createDirectory(
                atPath: roleDir,
                withIntermediateDirectories: true
            )
            try content.write(toFile: "\(roleDir)/CLAUDE.md", atomically: true, encoding: .utf8)
            try content.write(toFile: "\(roleDir)/AGENTS.md",  atomically: true, encoding: .utf8)
            logger.debug("Role files written to \(roleDir)")
        } catch {
            logger.error("Failed to write role files: \(error)")
        }
        return roleDir
    }

    /// 移除 Role 目录（取消分配时清理）
    func removeRoleDirectory(roleId: UUID) {
        let roleDir = PersistenceManager.shared.appDataURL
            .appendingPathComponent("roles/\(roleId.uuidString)")
            .path
        try? FileManager.default.removeItem(atPath: roleDir)
    }

    // MARK: - 文件内容构建（与 Maestri 格式完全一致）

    private func buildRoleFileContent(rolePrompt: String, workingDirectory: String) -> String {
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
}
