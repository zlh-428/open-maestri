import OSLog
import Foundation

/// 备份与恢复管理器
/// - 每小时自动生成 .omaestribak 备份（文件路径清单 JSON）
/// - 支持从备份文件恢复所有工作区数据
final class BackupManager {
    static let shared = BackupManager()
    private let logger = Logger.make(category: "BackupManager")
    private var timer: Timer?
    private let pm = PersistenceManager.shared

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
            let backupURL = backupDir.appendingPathComponent("\(timestamp).omaestribak")

            // 收集需要备份的文件
            var filesToBackup: [URL] = []
            for candidate in [pm.manifestURL, pm.appStateURL, pm.preferencesURL, pm.routinesURL] {
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

            // 新格式：存储文件路径 + base64 编码内容（支持真正恢复）
            var fileContents: [String: String] = [:]
            for fileURL in filesToBackup {
                if let fileData = try? Data(contentsOf: fileURL) {
                    fileContents[fileURL.path] = fileData.base64EncodedString()
                }
            }
            let payload: [String: Any] = ["files": fileContents, "version": 2]
            let data = try JSONSerialization.data(withJSONObject: payload)
            let tmp = backupURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            _ = try fm.replaceItem(at: backupURL, withItemAt: tmp, backupItemName: nil, resultingItemURL: nil)
            logger.info("Backup created: \(backupURL.lastPathComponent) (\(filesToBackup.count) files)")

            await pruneOldBackups(in: backupDir, keepCount: 24)
        } catch {
            logger.error("Backup failed: \(error)")
        }
    }

    // MARK: - 备份列表

    func listBackups() -> [URL] {
        let backupDir = pm.appDataURL.appendingPathComponent("backups")
        let fm = FileManager.default
        return (try? fm.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.creationDateKey]
        )
        .filter { $0.pathExtension == "omaestribak" }
        .sorted {
            let da = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da > db
        }) ?? []
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

    // MARK: - 清理旧备份

    private func pruneOldBackups(in dir: URL, keepCount: Int) async {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])
            .filter({ $0.pathExtension == "omaestribak" })
            .sorted(by: { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
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
