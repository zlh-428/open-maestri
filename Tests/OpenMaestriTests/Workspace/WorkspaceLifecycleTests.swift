import XCTest
@testable import open_maestri

/// 工作区端到端生命周期测试
final class WorkspaceLifecycleTests: XCTestCase {
    private var tmpDir: String!
    private let pm = PersistenceManager.shared

    override func setUpWithError() throws {
        tmpDir = NSTemporaryDirectory() + "ws-lifecycle-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: tmpDir)
        // 清理测试工作区目录
    }

    // MARK: - 工作区创建

    func testCreateWorkspaceDirectoryExists() throws {
        let wsId = UUID()
        try pm.ensureWorkspaceDirectoryExists(id: wsId)
        let wsDir = pm.workspaceDirURL(id: wsId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: wsDir.path),
                      "工作区目录应被创建")
        // 清理
        try? FileManager.default.removeItem(at: wsDir)
    }

    func testWorkspaceDocumentRoundTrip() throws {
        let wsId = UUID()
        try pm.ensureWorkspaceDirectoryExists(id: wsId)
        defer { try? FileManager.default.removeItem(at: pm.workspaceDirURL(id: wsId)) }

        // 创建并保存
        let payload = WorkspacePayload(id: wsId, name: "Test WS", workingDirectory: tmpDir)
        let doc = WorkspaceDocument(payload: payload)
        try pm.saveSync(doc, to: pm.workspaceURL(id: wsId))

        // 重新加载
        let loaded = try pm.loadWorkspace(id: wsId)
        XCTAssertEqual(loaded.payload.name, "Test WS")
        XCTAssertEqual(loaded.payload.workingDirectory, tmpDir)
        XCTAssertEqual(loaded.schemaVersion, Constants.schemaVersion)
        XCTAssertEqual(loaded.type, "workspace")
    }

    func testWorkspaceManagerLoadAfterSave() throws {
        let wsId = UUID()
        try pm.ensureWorkspaceDirectoryExists(id: wsId)
        defer { try? FileManager.default.removeItem(at: pm.workspaceDirURL(id: wsId)) }

        // 保存含节点的工作区
        var payload = WorkspacePayload(id: wsId, name: "Node WS", workingDirectory: tmpDir)
        let tc = TerminalContent(name: "Claude", agentType: "claude_code", command: "claude")
        let node = CanvasNode(
            frame: CGRect(x: 100, y: 200, width: 600, height: 400),
            content: .terminal(tc)
        )
        payload.nodes = [node]
        let doc = WorkspaceDocument(payload: payload)
        try pm.saveSync(doc, to: pm.workspaceURL(id: wsId))

        // 通过 WorkspaceManager 加载
        let entry = WorkspaceEntry(id: wsId, name: "Node WS", workingDirectory: tmpDir)
        let ws = WorkspaceManager(entry: entry)
        try ws.load()

        XCTAssertEqual(ws.nodes.count, 1)
        XCTAssertEqual(ws.nodes.first?.id, node.id)
        if case .terminal(let content) = ws.nodes.first?.content {
            XCTAssertEqual(content.agentType, "claude_code")
        } else {
            XCTFail("节点内容类型应为 terminal")
        }
    }

    // MARK: - 节点增删

    @MainActor
    func testAddAndRemoveNode() throws {
        let wsId = UUID()
        try pm.ensureWorkspaceDirectoryExists(id: wsId)
        defer { try? FileManager.default.removeItem(at: pm.workspaceDirURL(id: wsId)) }

        let entry = WorkspaceEntry(id: wsId, name: "Test", workingDirectory: tmpDir)
        let ws = WorkspaceManager(entry: entry)

        let tc = TerminalContent(name: "Shell", command: "zsh")
        let node = CanvasNode(frame: CGRect(x: 0, y: 0, width: 300, height: 200), content: .terminal(tc))

        ws.addNode(node)
        XCTAssertEqual(ws.nodes.count, 1)

        ws.removeNode(id: node.id)
        XCTAssertEqual(ws.nodes.count, 0)
    }

    @MainActor
    func testConnectionPersistence() throws {
        let wsId = UUID()
        try pm.ensureWorkspaceDirectoryExists(id: wsId)
        defer { try? FileManager.default.removeItem(at: pm.workspaceDirURL(id: wsId)) }

        let entry = WorkspaceEntry(id: wsId, name: "Conn WS", workingDirectory: tmpDir)
        let ws = WorkspaceManager(entry: entry)

        let idA = UUID(), idB = UUID()
        let conn = TerminalConnection(terminalIdA: idA, terminalIdB: idB)
        ws.addConnection(conn)

        XCTAssertEqual(ws.connections.count, 1)
        XCTAssertEqual(ws.connections.first?.terminalIdA, idA)

        // 验证持久化：保存后重新加载，连接应被还原
        try ws.saveSync()
        let ws2 = WorkspaceManager(entry: entry)
        try ws2.load()
        XCTAssertEqual(ws2.connections.count, 1, "保存并重新加载后连接应存在")
        XCTAssertEqual(ws2.connections.first?.terminalIdA, idA, "连接的 terminalIdA 应保持一致")

        // 删除连接
        ws.removeConnection(id: conn.id)
        XCTAssertEqual(ws.connections.count, 0)

        // 验证删除后持久化
        try ws.saveSync()
        let ws3 = WorkspaceManager(entry: entry)
        try ws3.load()
        XCTAssertEqual(ws3.connections.count, 0, "删除后保存重载连接应为空")
    }

    // MARK: - 快速保存

    @MainActor
    func testSaveCreatesDiskFile() throws {
        let wsId = UUID()
        try pm.ensureWorkspaceDirectoryExists(id: wsId)
        defer { try? FileManager.default.removeItem(at: pm.workspaceDirURL(id: wsId)) }

        let entry = WorkspaceEntry(id: wsId, name: "Save WS", workingDirectory: tmpDir)
        let ws = WorkspaceManager(entry: entry)
        try ws.saveSync()

        XCTAssertTrue(FileManager.default.fileExists(atPath: pm.workspaceURL(id: wsId).path),
                      "saveSync 后磁盘应有 workspace.json")
    }
}
