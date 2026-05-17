import Foundation
import OSLog

/// Note 文件管理器
/// - Note 内容存储为 .md 文件
/// - 支持 managed（~/.open-maestri/workspaces/{id}/notes/）和 custom（任意路径）两种存储模式
/// - 所有文件 I/O 通过 PersistenceManager 的原子写入
final class NoteFileManager {
    static let shared = NoteFileManager()
    private let logger = Logger.make(category: "NoteFileManager")
    private let pm = PersistenceManager.shared
    private init() {}

    // MARK: - 读取

    /// 读取 Note 内容
    /// - Parameter filePath: .md 文件绝对路径
    /// - Returns: 文件内容字符串
    func read(filePath: String) throws -> String {
        let url = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw MaestriError.noteReadFailed("File not found: \(filePath)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 读取 Note 内容（带行范围）
    /// 格式与 Maestri CLI 一致：`[14 lines total]\n1    内容...`
    func readWithLineRange(filePath: String, offset: Int? = nil, limit: Int? = nil) throws -> String {
        let content = try read(filePath: filePath)
        let lines = content.components(separatedBy: "\n")
        let total = lines.count

        let start = max(0, (offset ?? 1) - 1)
        let end = min(total, start + (limit ?? total))
        let selectedLines = Array(lines[start..<end])

        let header: String
        if let o = offset, let l = limit {
            header = "[lines \(o)-\(o + l - 1) of \(total)]"
        } else {
            header = "[\(total) lines total]"
        }

        let numbered = selectedLines.enumerated().map { idx, line in
            "\(start + idx + 1)    \(line)"
        }.joined(separator: "\n")

        return "\(header)\n\(numbered)"
    }

    // MARK: - 写入

    /// 完整替换 Note 内容
    func write(filePath: String, content: String) throws {
        let url = URL(fileURLWithPath: filePath)
        let data = Data(content.utf8)
        // 确保父目录存在
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItem(at: url, withItemAt: tmp, backupItemName: nil, resultingItemURL: nil)
        logger.debug("Note written: \(filePath)")
    }

    /// 局部编辑（替换第一个匹配的文本）
    func edit(filePath: String, oldText: String, newText: String) throws {
        let current = try read(filePath: filePath)
        guard current.contains(oldText) else {
            throw MaestriError.noteWriteFailed("Text '\(oldText)' not found in note")
        }
        let updated = current.replacingOccurrences(of: oldText, with: newText, range: current.range(of: oldText))
        try write(filePath: filePath, content: updated)
    }

    // MARK: - 路径管理

    /// 为新 Note 生成 managed 路径
    func managedPath(workspaceId: UUID, noteName: String) -> String {
        pm.notesDirURL(workspaceId: workspaceId)
            .appendingPathComponent("\(sanitizeFilename(noteName)).md")
            .path
    }

    /// 创建新 Note 文件（内容为空）
    func createNote(workspaceId: UUID, name: String) throws -> String {
        let path = managedPath(workspaceId: workspaceId, noteName: name)
        if !FileManager.default.fileExists(atPath: path) {
            try write(filePath: path, content: "")
        }
        return path
    }

    // MARK: - Note Chain 遍历（FR30）

    /// 遍历 Note Chain，收集所有连接的 Note 内容
    /// - Parameters:
    ///   - entryNote: 入口 Note 的 filePath
    ///   - visited: 已访问路径集合（防止循环）
    func readChain(entryNotePath: String, visited: inout Set<String>) throws -> String {
        guard !visited.contains(entryNotePath) else { return "" }
        visited.insert(entryNotePath)
        let content = try read(filePath: entryNotePath)
        return content
    }

    // MARK: - 工具

    private func sanitizeFilename(_ name: String) -> String {
        name.components(separatedBy: .init(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
