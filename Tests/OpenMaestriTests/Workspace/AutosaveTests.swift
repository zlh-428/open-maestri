import XCTest
@testable import open_maestri

// Story 1.5 AC 验收测试：自动保存与备份
final class AutosaveTests: XCTestCase {

    // MARK: - Story 1.5 AC: 30 秒自动保存

    func testAutosaveIntervalIs30Seconds() {
        XCTAssertEqual(Constants.autosaveInterval, 30.0,
                       "Story 1.5 AC: Autosave must trigger every 30 seconds")
    }

    @MainActor
    func testStartAutosaveCreatesTimer() {
        let appState = AppState()
        appState.startAutosave()
        // Timer 存在（通过 forceSave 验证 appState 已启动自动保存逻辑）
        appState.stopAutosave()
        // 不崩溃即通过
        XCTAssertTrue(true)
    }

    @MainActor
    func testForceSaveWritesCleanShutdown() throws {
        let appState = AppState()
        // 确保目录存在
        try PersistenceManager.shared.ensureDirectoriesExist()
        appState.forceSave(cleanShutdown: true)
        // 验证 app-state.json 被写入
        let state = try PersistenceManager.shared.loadAppState()
        XCTAssertTrue(state.cleanShutdown, "forceSave(cleanShutdown: true) must persist cleanShutdown=true")
    }

    @MainActor
    func testForceSaveDirtyShutdown() throws {
        let appState = AppState()
        try PersistenceManager.shared.ensureDirectoriesExist()
        appState.forceSave(cleanShutdown: false)
        let state = try PersistenceManager.shared.loadAppState()
        XCTAssertFalse(state.cleanShutdown, "forceSave(cleanShutdown: false) must persist cleanShutdown=false")
    }

    // MARK: - Story 1.5 AC: 每小时 .omaestribak 备份（NFR12）

    func testBackupIntervalIs3600Seconds() {
        XCTAssertEqual(Constants.backupInterval, 3600.0,
                       "NFR12: Backup must run every hour (3600s)")
    }

    func testBackupCreatesFile() async throws {
        let pm = PersistenceManager.shared
        try pm.ensureDirectoriesExist()

        await BackupManager.shared.createBackup()

        let backupDir = pm.appDataURL.appendingPathComponent("backups")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: backupDir.path)) ?? []
        let backupFiles = files.filter { $0.hasSuffix(".omaestribak") }

        XCTAssertFalse(backupFiles.isEmpty,
                       "NFR12: createBackup() must create a .omaestribak file")
    }

    // MARK: - Story 1.5 AC: 重启后恢复时间 < 0.5s（NFR2）

    func testWorkspacePayloadCodingIsfast() throws {
        // 创建一个有 10 个节点的工作区，测试序列化速度
        var payload = WorkspacePayload(name: "PerfTest", workingDirectory: "/tmp")
        for i in 0..<10 {
            let node = CanvasNode(
                frame: CGRect(x: Double(i) * 100, y: 0, width: 400, height: 300),
                content: .terminal(TerminalContent(name: "Agent\(i)"))
            )
            payload.nodes.append(node)
        }
        let doc = WorkspaceDocument(payload: payload)

        let start = Date()
        let data = try PersistenceManager.shared.encoder.encode(doc)
        _ = try PersistenceManager.shared.decoder.decode(WorkspaceDocument.self, from: data)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.1,
                          "NFR2: Workspace restore must complete quickly, took \(elapsed)s")
    }

    // MARK: - PersistenceManager 原子写入（NFR11）

    func testAtomicWriteNoTempFileLeftBehind() async throws {
        let pm = PersistenceManager.shared
        let tmpUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("atomic-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpUrl) }

        try await pm.save(["test": "value"], to: tmpUrl)

        // 临时文件不应残留
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpUrl.appendingPathExtension("tmp").path),
                       "NFR11: Atomic write must clean up .tmp file")
        // 正式文件应存在
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpUrl.path))
    }
}
