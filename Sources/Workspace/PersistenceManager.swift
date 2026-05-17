import Foundation
import OSLog

/// 数据持久化管理器
/// 所有文件 I/O 必须通过此类进行（ScrollbackStore 除外，性能原因）
final class PersistenceManager {
    static let shared = PersistenceManager()

    private let logger = Logger.make(category: "PersistenceManager")

    /// 应用数据根目录 ~/.open-maestri/
    var appDataURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(Constants.appDataDirectoryName)
    }

    var appStateURL: URL { appDataURL.appendingPathComponent("app-state.json") }
    var preferencesURL: URL { appDataURL.appendingPathComponent("preferences.json") }
    var manifestURL: URL { appDataURL.appendingPathComponent("manifest.json") }
    var routinesURL: URL { appDataURL.appendingPathComponent("routines.json") }
    var sidebarLayoutURL: URL { appDataURL.appendingPathComponent("sidebar-layout.json") }

    func workspaceURL(id: UUID) -> URL {
        appDataURL.appendingPathComponent("workspaces/\(id.uuidString)/workspace.json")
    }

    func workspaceDirURL(id: UUID) -> URL {
        appDataURL.appendingPathComponent("workspaces/\(id.uuidString)")
    }

    func notesDirURL(workspaceId: UUID) -> URL {
        workspaceDirURL(id: workspaceId).appendingPathComponent("notes")
    }

    func scrollbackURL(terminalId: UUID, workspaceId: UUID) -> URL {
        workspaceDirURL(id: workspaceId).appendingPathComponent("terminals/\(terminalId.uuidString).scrollback")
    }

    let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    private init() {}

    // MARK: - 目录初始化

    func ensureDirectoriesExist() throws {
        let dirs: [URL] = [
            appDataURL,
            appDataURL.appendingPathComponent("workspaces"),
            appDataURL.appendingPathComponent("roles"),
        ]
        for dir in dirs {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func ensureWorkspaceDirectoryExists(id: UUID) throws {
        let dirs: [URL] = [
            workspaceDirURL(id: id),
            notesDirURL(workspaceId: id),
            workspaceDirURL(id: id).appendingPathComponent("terminals"),
            workspaceDirURL(id: id).appendingPathComponent("snapshots"),
        ]
        for dir in dirs {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - 通用原子 Codable I/O

    func save<T: Encodable>(_ value: T, to url: URL) async throws {
        let data = try encoder.encode(value)
        try await Task.detached(priority: .background) {
            try self.atomicWrite(data, to: url)
        }.value
    }

    func saveSync<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try atomicWrite(data, to: url)
    }

    func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try migrating(data: data, type: type)
    }

    func loadIfExists<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try load(type, from: url)
    }

    // MARK: - 版本迁移钩子

    private func migrating<T: Decodable>(data: Data, type: T.Type) throws -> T {
        // 如果是 WorkspaceDocument，检查 schemaVersion
        if type == WorkspaceDocument.self {
            if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = raw["schemaVersion"] as? Int,
               version < Constants.schemaVersion {
                let migrated = try Migration_v1_to_v2.migrate(data: data)
                return try decoder.decode(type, from: migrated)
            }
        }
        return try decoder.decode(type, from: data)
    }

    // MARK: - 原子写入

    private func atomicWrite(_ data: Data, to url: URL) throws {
        // 确保父目录存在
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItem(
            at: url,
            withItemAt: tmp,
            backupItemName: nil,
            resultingItemURL: nil
        )
    }

    // MARK: - 高层工作区 API（Story 1.3/1.5 使用）

    func loadWorkspace(id: UUID) throws -> WorkspaceDocument {
        let url = workspaceURL(id: id)
        return try load(WorkspaceDocument.self, from: url)
    }

    func saveWorkspace(_ doc: WorkspaceDocument) async throws {
        let url = workspaceURL(id: doc.payload.id)
        try await save(doc, to: url)
    }

    func loadAppState() throws -> AppStateData {
        (try loadIfExists(AppStateData.self, from: appStateURL)) ?? AppStateData()
    }

    func saveAppState(_ state: AppStateData) throws {
        try saveSync(state, to: appStateURL)
    }

    func loadPreferences() throws -> Preferences {
        (try loadIfExists(Preferences.self, from: preferencesURL)) ?? Preferences()
    }

    /// 同步无抛出版本，供 HTTP 线程调用（返回默认值而非崩溃）
    func loadPreferencesSync() -> Preferences {
        (try? loadPreferences()) ?? Preferences()
    }

    func savePreferences(_ prefs: Preferences) throws {
        try saveSync(prefs, to: preferencesURL)
    }

    func loadManifest() throws -> WorkspaceManifest {
        (try loadIfExists(WorkspaceManifest.self, from: manifestURL)) ?? WorkspaceManifest()
    }

    func saveManifest(_ manifest: WorkspaceManifest) throws {
        try saveSync(manifest, to: manifestURL)
    }

    func loadSidebarLayout() throws -> SidebarLayout {
        (try loadIfExists(SidebarLayout.self, from: sidebarLayoutURL)) ?? SidebarLayout()
    }

    func saveSidebarLayout(_ layout: SidebarLayout) throws {
        try saveSync(layout, to: sidebarLayoutURL)
    }
}
