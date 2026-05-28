import OSLog
import Foundation

/// 备份与恢复管理器
/// - 每小时自动生成 .omaestribak 备份（文件路径清单 JSON）
/// - 支持从备份文件恢复所有工作区数据
/// - 支持导出完整备份到用户指定路径 / 从外部文件导入恢复
final class BackupManager {
    static let shared = BackupManager()
    private let logger = Logger.make(category: "BackupManager")
    private var timer: Timer?
    private let pm = PersistenceManager.shared

    /// 上次自动备份完成时间（运行时状态）
    private(set) var lastBackupTime: Date?

    private init() {}

    // MARK: - 定时备份

    func startHourlyBackups() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: Constants.backupInterval,
            repeats: true
        ) { [weak self] _ in
            Task.detached(priority: .background) { [weak self] in
                await self?.createBackup()
            }
        }
        logger.debug("Hourly backups started (interval: \(Constants.backupInterval)s)")
    }

    func stopBackups() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 备份创建

    func createBackup() async {
        let fm = FileManager.default
        let backupDir = pm.appDataURL.appendingPathComponent("backups")
        do {
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let backupURL = backupDir.appendingPathComponent("open-maestri-\(timestamp).omaestribak")

            let data = try buildBackupData()
            let tmp = backupURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            if fm.fileExists(atPath: backupURL.path) {
                _ = try fm.replaceItem(at: backupURL, withItemAt: tmp, backupItemName: nil, resultingItemURL: nil)
            } else {
                try fm.moveItem(at: tmp, to: backupURL)
            }
            lastBackupTime = Date()
            logger.info("Backup created: \(backupURL.lastPathComponent)")

            await pruneOldBackups(in: backupDir, keepCount: 24)
        } catch {
            logger.error("Backup failed: \(error)")
        }
    }

    // MARK: - 导出完整备份（用户手动触发，保存到指定路径）

    /// 将所有应用数据导出为单个备份文件
    /// - Parameter destinationURL: 用户通过 NSSavePanel 选择的目标路径
    func exportBackup(to destinationURL: URL) throws {
        let data = try buildBackupData()
        try data.write(to: destinationURL, options: .atomic)
        logger.info("Backup exported to: \(destinationURL.path)")
    }

    /// 从外部备份文件导入恢复（用户通过 NSOpenPanel 选择）
    /// - Parameter sourceURL: 外部 .omaestribak 文件路径
    /// - Returns: 成功恢复的文件数量
    @discardableResult
    func importBackup(from sourceURL: URL) throws -> Int {
        return try restoreFromBackup(url: sourceURL)
    }

    // MARK: - 备份列表

    func listBackups() -> [URL] {
        let backupDir = pm.appDataURL.appendingPathComponent("backups")
        let fm = FileManager.default
        return (try? fm.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        .filter { $0.pathExtension == "omaestribak" }
        .sorted {
            let da = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }) ?? []
    }

    /// 获取上次备份的时间（从文件系统读取，用于首次启动时显示）
    func lastBackupDate() -> Date? {
        if let cached = lastBackupTime { return cached }
        guard let latest = listBackups().first else { return nil }
        return (try? latest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    }

    // MARK: - 恢复

    /// 从备份文件恢复数据（将备份的文件内容复制回原路径）
    /// - Parameter backupURL: .omaestribak 文件 URL
    /// - Returns: 成功恢复的文件数量
    @discardableResult
    func restoreFromBackup(url backupURL: URL) throws -> Int {
        let fm = FileManager.default
        let data = try Data(contentsOf: backupURL)

        // 新格式：{"files": {"path": "base64content", ...}}
        // 旧格式（路径清单）：["path1", "path2", ...]
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let files = dict["files"] as? [String: String] {
            // 新格式恢复
            var restoredCount = 0
            for (path, base64) in files {
                guard let fileData = Data(base64Encoded: base64) else { continue }
                let url = URL(fileURLWithPath: path)
                do {
                    try fm.createDirectory(at: url.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
                    try fileData.write(to: url, options: .atomic)
                    restoredCount += 1
                } catch {
                    logger.error("Restore failed for \(path): \(error)")
                }
            }
            logger.info("Restored \(restoredCount)/\(files.count) files from \(backupURL.lastPathComponent)")
            NotificationCenter.default.post(name: .backupRestored, object: nil)
            return restoredCount
        } else {
            // 旧格式：仅路径清单，无法真正恢复
            let filePaths = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            let available = filePaths.filter { fm.fileExists(atPath: $0) }.count
            logger.warning("Backup \(backupURL.lastPathComponent) uses old format (path-only), cannot restore content")
            return available
        }
    }

    // MARK: - 存储用量计算

    /// 计算整个应用数据目录的总大小
    func totalStorageSize() -> Int64 {
        return directorySize(at: pm.appDataURL)
    }

    /// 计算各工作区的存储大小
    /// - Returns: [(workspaceName, workspaceId, sizeInBytes)]
    func workspaceStorageSizes() -> [(name: String, id: UUID, size: Int64)] {
        let fm = FileManager.default
        let wsDir = pm.appDataURL.appendingPathComponent("workspaces")
        guard let entries = try? fm.contentsOfDirectory(atPath: wsDir.path) else { return [] }

        var results: [(name: String, id: UUID, size: Int64)] = []
        for entry in entries {
            guard let uuid = UUID(uuidString: entry) else { continue }
            let wsPath = wsDir.appendingPathComponent(entry)
            let size = directorySize(at: wsPath)
            // 尝试读取工作区名称
            let wsJsonPath = wsPath.appendingPathComponent("workspace.json")
            var name = entry
            if let data = try? Data(contentsOf: wsJsonPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let payload = json["payload"] as? [String: Any],
               let wsName = payload["name"] as? String {
                name = wsName
            }
            results.append((name: name, id: uuid, size: size))
        }
        return results.sorted { $0.size > $1.size }
    }

    /// 递归计算目录大小
    private func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  values.isDirectory == false,
                  let size = values.fileSize else { continue }
            totalSize += Int64(size)
        }
        return totalSize
    }

    // MARK: - 重置所有数据

    /// 删除所有应用数据（危险操作，调用前需确认）
    func deleteAllData() throws {
        let fm = FileManager.default
        let appDataPath = pm.appDataURL.path
        guard fm.fileExists(atPath: appDataPath) else { return }

        // 逐个删除子目录和文件，而非递归删除根目录
        let contents = try fm.contentsOfDirectory(atPath: appDataPath)
        for item in contents {
            let itemPath = pm.appDataURL.appendingPathComponent(item).path
            try fm.removeItem(atPath: itemPath)
        }
        // 重新创建基础目录结构
        try pm.ensureDirectoriesExist()
        logger.warning("All application data has been deleted and directories recreated")
    }

    // MARK: - 私有辅助

    /// 构建备份数据（收集所有文件并打包为 JSON）
    private func buildBackupData() throws -> Data {
        let fm = FileManager.default
        var filesToBackup: [URL] = []
        for candidate in [pm.manifestURL, pm.appStateURL, pm.preferencesURL, pm.routinesURL, pm.sidebarLayoutURL] {
            if fm.fileExists(atPath: candidate.path) {
                filesToBackup.append(candidate)
            }
        }
        let wsDir = pm.appDataURL.appendingPathComponent("workspaces")
        if let workspaceIds = try? fm.contentsOfDirectory(atPath: wsDir.path) {
            for wsId in workspaceIds {
                let wsFile = wsDir.appendingPathComponent("\(wsId)/workspace.json")
                if fm.fileExists(atPath: wsFile.path) {
                    filesToBackup.append(wsFile)
                }
                // 备份 notes
                let notesDir = wsDir.appendingPathComponent("\(wsId)/notes")
                if let notes = try? fm.contentsOfDirectory(atPath: notesDir.path) {
                    for note in notes where note.hasSuffix(".md") {
                        filesToBackup.append(notesDir.appendingPathComponent(note))
                    }
                }
            }
        }
        // 备份 roles
        let rolesDir = pm.appDataURL.appendingPathComponent("roles")
        if let roleIds = try? fm.contentsOfDirectory(atPath: rolesDir.path) {
            for roleId in roleIds {
                let roleDir = rolesDir.appendingPathComponent(roleId)
                if let roleFiles = try? fm.contentsOfDirectory(atPath: roleDir.path) {
                    for file in roleFiles {
                        filesToBackup.append(roleDir.appendingPathComponent(file))
                    }
                }
            }
        }

        // 存储文件路径 + base64 编码内容
        var fileContents: [String: String] = [:]
        for fileURL in filesToBackup {
            if let fileData = try? Data(contentsOf: fileURL) {
                // 使用相对路径存储（相对于 appDataURL），便于恢复到不同位置
                fileContents[fileURL.path] = fileData.base64EncodedString()
            }
        }
        let payload: [String: Any] = [
            "files": fileContents,
            "version": 2,
            "app": "open-maestri",
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "fileCount": filesToBackup.count
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: - 清理旧备份

    private func pruneOldBackups(in dir: URL, keepCount: Int) async {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter({ $0.pathExtension == "omaestribak" })
            .sorted(by: { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return da > db
            }) else { return }

        for file in files.dropFirst(keepCount) {
            try? fm.removeItem(at: file)
        }
    }
}

extension Notification.Name {
    static let backupRestored = Notification.Name("OpenMaestri.backupRestored")
}
