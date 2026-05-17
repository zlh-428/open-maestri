import XCTest
@testable import open_maestri

// Story 1.4 + 1.5 AC：WorkspaceManager 持久化测试
final class WorkspaceManagerTests: XCTestCase {

    // MARK: - 初始化

    func testInitFromEntry() {
        let entry = WorkspaceEntry(name: "Test WS", workingDirectory: "/projects/test")
        let manager = WorkspaceManager(entry: entry)
        XCTAssertEqual(manager.id, entry.id)
        XCTAssertEqual(manager.name, "Test WS")
        XCTAssertEqual(manager.workingDirectory, "/projects/test")
    }

    func testInitWithDefaultsIsEmpty() {
        let manager = WorkspaceManager(name: "Empty", workingDirectory: "/tmp")
        XCTAssertTrue(manager.nodes.isEmpty)
        XCTAssertTrue(manager.connections.isEmpty)
        XCTAssertEqual(manager.canvasZoom, 1.0)
    }

    // MARK: - 节点管理

    func testAddNode() {
        let manager = WorkspaceManager(name: "WS", workingDirectory: "/tmp")
        let node = CanvasNode(
            frame: CGRect(x: 0, y: 0, width: 400, height: 300),
            content: .terminal(TerminalContent(name: "Agent1"))
        )
        manager.addNode(node)
        XCTAssertEqual(manager.nodes.count, 1)
        XCTAssertEqual(manager.nodes[0].id, node.id)
    }

    func testRemoveNode() {
        let manager = WorkspaceManager(name: "WS", workingDirectory: "/tmp")
        let node = CanvasNode(
            frame: CGRect(x: 0, y: 0, width: 400, height: 300),
            content: .stickyNote(StickyNoteContent(name: "Note"))
        )
        manager.addNode(node)
        manager.removeNode(id: node.id)
        XCTAssertTrue(manager.nodes.isEmpty)
    }

    func testUpdateNodeFrame() {
        let manager = WorkspaceManager(name: "WS", workingDirectory: "/tmp")
        let node = CanvasNode(
            frame: CGRect(x: 0, y: 0, width: 400, height: 300),
            content: .terminal(TerminalContent(name: "Agent"))
        )
        manager.addNode(node)

        let newFrame = CGRect(x: 100, y: 200, width: 500, height: 350)
        manager.updateNodeFrame(id: node.id, frame: newFrame)

        XCTAssertEqual(manager.nodes[0].frame.origin.x, 100, accuracy: 0.01)
        XCTAssertEqual(manager.nodes[0].frame.size.width, 500, accuracy: 0.01)
    }

    // MARK: - 持久化（Story 1.5 AC）

    func testSaveAndLoad() async throws {
        let pm = PersistenceManager.shared
        try pm.ensureDirectoriesExist()

        let wsId = UUID()
        try pm.ensureWorkspaceDirectoryExists(id: wsId)

        let manager = WorkspaceManager(id: wsId, name: "PersistTest", workingDirectory: "/tmp")
        manager.addNode(CanvasNode(
            frame: CGRect(x: 100, y: 200, width: 400, height: 300),
            content: .terminal(TerminalContent(name: "TestAgent"))
        ))
        manager.canvasZoom = 1.5
        manager.canvasOrigin = CGPoint(x: 9850, y: 8550)

        // 保存
        try await manager.save()

        // 加载验证
        let loaded = WorkspaceManager(id: wsId, name: "PersistTest", workingDirectory: "/tmp")
        try loaded.load()

        XCTAssertEqual(loaded.nodes.count, 1)
        XCTAssertEqual(loaded.canvasZoom, 1.5, accuracy: 0.01)
        XCTAssertEqual(loaded.canvasOrigin.x, 9850, accuracy: 0.01)

        // 清理
        try? FileManager.default.removeItem(at: pm.workspaceDirURL(id: wsId))
    }

    // MARK: - NoteRegistry

    func testNoteRegistryRegisterAndResolve() {
        let reg = NoteRegistry.shared
        let path = "/tmp/test-\(UUID().uuidString).md"
        reg.register(name: "MyNote", filePath: path)
        XCTAssertEqual(reg.path(forName: "MyNote"), path)
        reg.unregister(name: "MyNote")
        XCTAssertNil(reg.path(forName: "MyNote"))
    }

    func testNoteRegistryCaseInsensitive() {
        let reg = NoteRegistry.shared
        reg.register(name: "SpecNote", filePath: "/tmp/spec.md")
        XCTAssertNotNil(reg.path(forName: "specnote"))
        reg.unregister(name: "SpecNote")
    }

    func testNoteRegistryThreadSafety() async {
        let reg = NoteRegistry.shared
        // 并发写入不应崩溃
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    reg.register(name: "note\(i)", filePath: "/tmp/\(i).md")
                }
            }
        }
        // 清理
        for i in 0..<100 { reg.unregister(name: "note\(i)") }
    }
}
