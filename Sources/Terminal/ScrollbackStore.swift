import Foundation
import OSLog

/// Scrollback 持久化行条目
struct ScrollbackEntry: Codable {
    var attributes: [String]    // 终端属性（颜色、样式等）
    var text: String
}

/// 终端 Scrollback 存储
/// - 格式：JSON Array of ScrollbackEntry
/// - 原子写入防止数据损坏（NFR11）
/// - 路径：~/.open-maestri/workspaces/{wsId}/terminals/{terminalId}.scrollback
final class ScrollbackStore {
    private let logger = Logger.make(category: "ScrollbackStore")
    private let pm = PersistenceManager.shared

    // MARK: - 保存

    func save(entries: [ScrollbackEntry], terminalId: UUID, workspaceId: UUID) async throws {
        let url = pm.scrollbackURL(terminalId: terminalId, workspaceId: workspaceId)
        // 确保目录存在
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(entries)
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItem(at: url, withItemAt: tmp, backupItemName: nil, resultingItemURL: nil)
        logger.debug("Scrollback saved: \(entries.count) lines for terminal \(terminalId.uuidString.prefix(8))")
    }

    // MARK: - 加载

    func load(terminalId: UUID, workspaceId: UUID) throws -> [ScrollbackEntry] {
        let url = pm.scrollbackURL(terminalId: terminalId, workspaceId: workspaceId)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ScrollbackEntry].self, from: data)
    }

    // MARK: - 追加（增量写入）

    func append(lines: [ScrollbackEntry], terminalId: UUID, workspaceId: UUID) async throws {
        var existing = (try? load(terminalId: terminalId, workspaceId: workspaceId)) ?? []
        existing.append(contentsOf: lines)
        // 最多保留最近 10000 行
        if existing.count > 10000 {
            existing = Array(existing.suffix(10000))
        }
        try await save(entries: existing, terminalId: terminalId, workspaceId: workspaceId)
    }
}
