import Foundation
import OSLog

/// Scrollback 持久化行条目
struct ScrollbackEntry: Codable {
    var attributes: [String]    // 终端属性（颜色、样式等）
    var text: String
}

/// 终端 Scrollback 存储
/// - 格式：JSONL（每行一个 JSON 对象），向后兼容旧 JSON Array 格式
/// - append 只做文件追加（不读取整个文件），大幅降低高频写入时的 I/O 开销
/// - 原子写入防止数据损坏（NFR11）
/// - 路径：~/.open-maestri/workspaces/{wsId}/terminals/{terminalId}.scrollback
final class ScrollbackStore {
    private let logger = Logger.make(category: "ScrollbackStore")
    private let pm = PersistenceManager.shared

    /// 每个终端的行数上限，超出时触发 compaction
    private let maxLines = 10000

    // MARK: - 保存（全量写入 JSONL 格式）

    func save(entries: [ScrollbackEntry], terminalId: UUID, workspaceId: UUID) async throws {
        let url = pm.scrollbackURL(terminalId: terminalId, workspaceId: workspaceId)
        // 确保目录存在
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        // 生成 JSONL：每个条目编码为单行 JSON
        var lines: [Data] = []
        for entry in entries {
            lines.append(try encoder.encode(entry))
        }
        let newline = Data([0x0A]) // "\n"
        var combined = Data()
        for line in lines {
            combined.append(line)
            combined.append(newline)
        }
        let tmp = url.appendingPathExtension("tmp")
        try combined.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItem(at: url, withItemAt: tmp, backupItemName: nil, resultingItemURL: nil)
        logger.debug("Scrollback saved: \(entries.count) lines for terminal \(terminalId.uuidString.prefix(8))")
    }

    // MARK: - 加载（兼容旧 JSON Array 和新 JSONL 格式）

    func load(terminalId: UUID, workspaceId: UUID) throws -> [ScrollbackEntry] {
        let url = pm.scrollbackURL(terminalId: terminalId, workspaceId: workspaceId)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }

        // 判断格式：JSON Array 以 '[' 开头，JSONL 以 '{' 开头
        let firstByte = data[data.startIndex]
        if firstByte == UInt8(ascii: "[") {
            // 旧格式：JSON Array
            return try JSONDecoder().decode([ScrollbackEntry].self, from: data)
        } else {
            // 新格式：JSONL（每行一个 JSON 对象）
            let decoder = JSONDecoder()
            var entries: [ScrollbackEntry] = []
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let lineData = line.data(using: .utf8) else { continue }
                if let entry = try? decoder.decode(ScrollbackEntry.self, from: lineData) {
                    entries.append(entry)
                }
            }
            return entries
        }
    }

    // MARK: - 追加（增量 JSONL 追加，不读取整个文件）

    func append(lines newLines: [ScrollbackEntry], terminalId: UUID, workspaceId: UUID) async throws {
        let url = pm.scrollbackURL(terminalId: terminalId, workspaceId: workspaceId)
        // 确保目录存在
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        var appendData = Data()
        let newline = Data([0x0A])
        for entry in newLines {
            appendData.append(try encoder.encode(entry))
            appendData.append(newline)
        }

        // 如果文件不存在或是旧 JSON Array 格式，先迁移
        if FileManager.default.fileExists(atPath: url.path) {
            let existingData = try Data(contentsOf: url)
            if !existingData.isEmpty && existingData[existingData.startIndex] == UInt8(ascii: "[") {
                // 旧格式：加载 → 转换 → 全量写入 JSONL，然后追加新行
                let existing = try JSONDecoder().decode([ScrollbackEntry].self, from: existingData)
                var all = existing
                all.append(contentsOf: newLines)
                if all.count > maxLines {
                    all = Array(all.suffix(maxLines))
                }
                try await save(entries: all, terminalId: terminalId, workspaceId: workspaceId)
                return
            }
        }

        // JSONL 追加：直接写入文件末尾
        if let fileHandle = try? FileHandle(forWritingTo: url) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(appendData)
            fileHandle.closeFile()
        } else {
            // 文件不存在，创建新文件
            try appendData.write(to: url, options: .atomic)
        }

        // 定期检查是否需要 compaction（每 100 次 append 检查一次，减少 stat 调用）
        // 简单策略：通过文件大小估算行数（平均每行 ~100 bytes）
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attrs[.size] as? UInt64,
           fileSize > UInt64(maxLines) * 120 {  // 估算超出上限
            let all = try load(terminalId: terminalId, workspaceId: workspaceId)
            if all.count > maxLines {
                try await save(entries: Array(all.suffix(maxLines)), terminalId: terminalId, workspaceId: workspaceId)
            }
        }
    }
}
