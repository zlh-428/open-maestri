import Foundation
import OSLog

final class NoteHandler {
    static let shared = NoteHandler()
    private let logger = Logger.make(category: "NoteHandler")
    private let nm = NoteFileManager.shared
    private init() {}

    func handle(args: [String], terminalId: UUID?) -> String {
        guard args.count >= 2 else {
            return "error: usage: omaestri note <read|write|edit|create> ..."
        }
        switch args[1] {
        case "read":   return handleRead(args: args, terminalId: terminalId)
        case "write":  return handleWrite(args: args, terminalId: terminalId)
        case "edit":   return handleEdit(args: args, terminalId: terminalId)
        default: return "error: unknown note subcommand '\(args[1])'. Valid: read|write|edit|create"
        }
    }

    func handleAsync(args: [String], terminalId: UUID?) async -> String {
        guard args.count >= 2 else {
            return "error: usage: omaestri note <read|write|edit|create> ..."
        }
        switch args[1] {
        case "read":   return handleRead(args: args, terminalId: terminalId)
        case "write":  return handleWrite(args: args, terminalId: terminalId)
        case "edit":   return handleEdit(args: args, terminalId: terminalId)
        case "create": return await handleCreate(args: args, terminalId: terminalId)
        default: return "error: unknown note subcommand '\(args[1])'. Valid: read|write|edit|create"
        }
    }

    // MARK: - read（FR35, FR36）

    private func handleRead(args: [String], terminalId: UUID?) -> String {
        guard args.count >= 3 else {
            return "error: usage: omaestri note read \"NoteName\""
        }
        let noteName = args[2]

        guard let filePath = resolveNotePath(name: noteName, terminalId: terminalId) else {
            return "error: note '\(noteName)' not found in connections"
        }

        do {
            return try nm.read(filePath: filePath)
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    // MARK: - write（FR35 AC：完整替换 Note 内容，画布实时更新）

    private func handleWrite(args: [String], terminalId: UUID?) -> String {
        guard args.count >= 4 else {
            return "error: usage: omaestri note write \"NoteName\" \"content\""
        }
        let noteName = args[2]
        let content  = args[3]

        guard let filePath = resolveNotePath(name: noteName, terminalId: terminalId) else {
            return "error: note '\(noteName)' not found in connections"
        }

        do {
            try nm.write(filePath: filePath, content: content)
            logger.debug("Note '\(noteName)' written (\(content.count) chars)")
            return "OK"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    // MARK: - edit（FR35 AC：替换第一个匹配文本）

    private func handleEdit(args: [String], terminalId: UUID?) -> String {
        guard args.count >= 5 else {
            return "error: usage: omaestri note edit \"NoteName\" \"oldText\" \"newText\""
        }
        let noteName = args[2]
        let oldText  = args[3]
        let newText  = args[4]

        guard let filePath = resolveNotePath(name: noteName, terminalId: terminalId) else {
            return "error: note '\(noteName)' not found in connections"
        }

        do {
            try nm.edit(filePath: filePath, oldText: oldText, newText: newText)
            return "OK"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    // MARK: - create（FR35 AC：在画布创建新 Note 并连接当前终端）

    private func handleCreate(args: [String], terminalId: UUID?) async -> String {
        let initialContent = args.count >= 3 ? args[2] : ""
        let noteName = "Note-\(UUID().uuidString.prefix(8))"
        let pm = PersistenceManager.shared

        // 通过 terminalId 查找所属工作区，写入正确的 workspaces/{id}/notes/ 目录
        let workspaceId: UUID?
        if let tid = terminalId {
            workspaceId = await MainActor.run { TerminalManager.shared.terminalWorkspaceMap[tid] }
        } else {
            workspaceId = nil
        }

        do {
            let notesDir: URL
            if let wsId = workspaceId {
                notesDir = pm.notesDirURL(workspaceId: wsId)
            } else {
                // 无法确定工作区时 fallback 到全局目录（不应发生）
                notesDir = pm.appDataURL.appendingPathComponent("notes")
            }
            try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
            let path = notesDir.appendingPathComponent("\(noteName).md").path
            try nm.write(filePath: path, content: initialContent)
            NoteRegistry.shared.register(name: noteName, filePath: path)
            logger.info("Note '\(noteName)' created at \(path)")
            return noteName
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    // MARK: - Note 路径解析

    /// 通过 Note 名称解析文件路径
    /// 解析策略（优先级顺序）：
    /// 1. 从 NoteRegistry（运行时缓存）查找已注册的 Note
    /// 2. 在 ~/.open-maestri/ 下扫描 notes/ 目录匹配文件名
    private func resolveNotePath(name: String, terminalId: UUID?) -> String? {
        // 策略 1：从 NoteRegistry 查找
        if let path = NoteRegistry.shared.path(forName: name) {
            return path
        }

        // 策略 2：扫描所有工作区的 notes 目录
        let pm = PersistenceManager.shared
        let wsDir = pm.appDataURL.appendingPathComponent("workspaces")
        let fm = FileManager.default
        if let workspaceIds = try? fm.contentsOfDirectory(atPath: wsDir.path) {
            for wsId in workspaceIds {
                let notesDir = wsDir.appendingPathComponent("\(wsId)/notes")
                let candidates = [
                    notesDir.appendingPathComponent("\(name).md").path,
                    notesDir.appendingPathComponent(name).path,
                ]
                for path in candidates {
                    if fm.fileExists(atPath: path) { return path }
                }
                // 模糊匹配：文件名包含 name
                if let files = try? fm.contentsOfDirectory(atPath: notesDir.path) {
                    if let match = files.first(where: {
                        $0.lowercased().contains(name.lowercased()) && $0.hasSuffix(".md")
                    }) {
                        return notesDir.appendingPathComponent(match).path
                    }
                }
            }
        }

        // 策略 3：全局 notes 目录（fallback）
        let globalNotesPath = pm.appDataURL.appendingPathComponent("notes/\(name).md").path
        if fm.fileExists(atPath: globalNotesPath) { return globalNotesPath }

        return nil
    }
}

// MARK: - NoteRegistry（运行时 Note 路径缓存）

/// Note 节点路径注册表，由画布在创建/连接 Note 时更新
/// 允许 NoteHandler 在 HTTP 线程中查询 Note 路径而不需要 @MainActor
final class NoteRegistry {
    static let shared = NoteRegistry()
    private var registry: [String: String] = [:]        // name → filePath
    private var nodeIdRegistry: [UUID: String] = [:]    // nodeId → name
    private let lock = NSLock()
    private init() {}

    func register(name: String, filePath: String, nodeId: UUID? = nil) {
        lock.lock(); defer { lock.unlock() }
        registry[name] = filePath
        if let nodeId { nodeIdRegistry[nodeId] = name }
    }

    func unregister(name: String, nodeId: UUID? = nil) {
        lock.lock(); defer { lock.unlock() }
        registry.removeValue(forKey: name)
        if let nodeId { nodeIdRegistry.removeValue(forKey: nodeId) }
    }

    /// 通过 nodeId 反查 name 后完整删除两个映射（节点删除时调用）
    func unregisterByNodeId(_ nodeId: UUID) {
        lock.lock(); defer { lock.unlock() }
        if let name = nodeIdRegistry.removeValue(forKey: nodeId) {
            registry.removeValue(forKey: name)
        }
    }

    func path(forName name: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return registry[name] ?? registry.first { $0.key.lowercased() == name.lowercased() }?.value
    }

    func name(forNodeId nodeId: UUID) -> String? {
        lock.lock(); defer { lock.unlock() }
        return nodeIdRegistry[nodeId]
    }
}
