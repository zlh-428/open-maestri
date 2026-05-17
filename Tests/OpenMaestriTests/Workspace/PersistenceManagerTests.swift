import XCTest
import CoreGraphics
@testable import open_maestri

final class PersistenceManagerTests: XCTestCase {
    let pm = PersistenceManager.shared

    // MARK: - AC1: WorkspaceDocument 结构验证

    func testWorkspaceDocumentStructure() throws {
        let payload = WorkspacePayload(name: "Test", workingDirectory: "/tmp")
        let doc = WorkspaceDocument(payload: payload)
        XCTAssertEqual(doc.schemaVersion, 2)
        XCTAssertEqual(doc.type, "workspace")
        XCTAssertEqual(doc.payload.name, "Test")
    }

    // AC: schemaVersion 必须为 2
    func testSchemaVersionIsTwo() {
        let payload = WorkspacePayload(name: "Test", workingDirectory: "/tmp")
        let doc = WorkspaceDocument(payload: payload)
        XCTAssertEqual(doc.schemaVersion, Constants.schemaVersion)
        XCTAssertEqual(doc.schemaVersion, 2)
    }

    // AC: WorkspacePayload 包含所有必要字段
    func testWorkspacePayloadAllFields() throws {
        let payload = WorkspacePayload(name: "MyWS", workingDirectory: "/home/user")
        XCTAssertNotNil(payload.id)
        XCTAssertEqual(payload.name, "MyWS")
        XCTAssertEqual(payload.workingDirectory, "/home/user")
        XCTAssertTrue(payload.nodes.isEmpty)
        XCTAssertTrue(payload.connections.isEmpty)
        XCTAssertTrue(payload.noteConnections.isEmpty)
        XCTAssertTrue(payload.portalConnections.isEmpty)
        XCTAssertTrue(payload.portalToPortalConnections.isEmpty)
        XCTAssertEqual(payload.canvasZoom, 1.0)
    }

    // MARK: - AC2: CanvasNode frame [[x,y],[w,h]] 编解码

    func testCanvasNodeFrameEncoding() throws {
        let frame = CGRect(x: 100, y: 200, width: 300, height: 400)
        let content = NodeContent.stickyNote(StickyNoteContent(name: "note1"))
        let node = CanvasNode(frame: frame, content: content)

        let data = try pm.encoder.encode(node)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let frameArr = try XCTUnwrap(json["frame"] as? [[Double]])
        XCTAssertEqual(frameArr[0][0], 100.0)
        XCTAssertEqual(frameArr[0][1], 200.0)
        XCTAssertEqual(frameArr[1][0], 300.0)
        XCTAssertEqual(frameArr[1][1], 400.0)
    }

    func testCanvasNodeFrameDecoding() throws {
        let frame = CGRect(x: 50, y: 60, width: 250, height: 150)
        let content = NodeContent.terminal(TerminalContent(name: "term1"))
        let node = CanvasNode(frame: frame, content: content)

        let data = try pm.encoder.encode(node)
        let decoded = try pm.decoder.decode(CanvasNode.self, from: data)
        XCTAssertEqual(decoded.frame.origin.x, 50, accuracy: 0.01)
        XCTAssertEqual(decoded.frame.origin.y, 60, accuracy: 0.01)
        XCTAssertEqual(decoded.frame.size.width, 250, accuracy: 0.01)
        XCTAssertEqual(decoded.frame.size.height, 150, accuracy: 0.01)
    }

    // MARK: - AC3: NodeContent 枚举 discriminated union

    func testNodeContentTerminalRoundTrip() throws {
        let content = NodeContent.terminal(TerminalContent(name: "claude", agentType: "claude_code"))
        let data = try pm.encoder.encode(content)
        let decoded = try pm.decoder.decode(NodeContent.self, from: data)
        guard case .terminal(let tc) = decoded else {
            XCTFail("Expected terminal content"); return
        }
        XCTAssertEqual(tc.name, "claude")
        XCTAssertEqual(tc.agentType, "claude_code")
    }

    func testNodeContentStickyNoteRoundTrip() throws {
        let content = NodeContent.stickyNote(StickyNoteContent(name: "note"))
        let data = try pm.encoder.encode(content)
        let decoded = try pm.decoder.decode(NodeContent.self, from: data)
        guard case .stickyNote(let nc) = decoded else {
            XCTFail("Expected stickyNote content"); return
        }
        XCTAssertEqual(nc.color, Constants.noteDefaultColor)
    }

    // MARK: - AC4: 日期字段 ISO8601 UTC

    func testDateFieldsAreISO8601() throws {
        let payload = WorkspacePayload(name: "DateTest", workingDirectory: "/tmp")
        let doc = WorkspaceDocument(payload: payload)
        let data = try pm.encoder.encode(doc)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let innerPayload = try XCTUnwrap(json["payload"] as? [String: Any])
        let createdAt = try XCTUnwrap(innerPayload["createdAt"] as? String)
        // ISO8601 格式：yyyy-MM-ddTHH:mm:ssZ
        XCTAssertTrue(createdAt.contains("T"), "createdAt should be ISO8601: \(createdAt)")
        XCTAssertTrue(createdAt.contains("Z") || createdAt.contains("+"), "createdAt should be UTC: \(createdAt)")
    }

    // MARK: - AC5: 完整 WorkspaceDocument 序列化/反序列化

    func testFullWorkspaceDocumentRoundTrip() throws {
        var payload = WorkspacePayload(name: "FullTest", workingDirectory: "/projects/test")

        // 添加 3 个终端节点
        let t1 = CanvasNode(frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                            content: .terminal(TerminalContent(name: "Agent1")))
        let t2 = CanvasNode(frame: CGRect(x: 500, y: 0, width: 400, height: 300),
                            content: .terminal(TerminalContent(name: "Agent2")))
        let t3 = CanvasNode(frame: CGRect(x: 1000, y: 0, width: 400, height: 300),
                            content: .terminal(TerminalContent(name: "Agent3")))
        // 添加 1 个 Note 节点
        let n1 = CanvasNode(frame: CGRect(x: 0, y: 400, width: 260, height: 150),
                            content: .stickyNote(StickyNoteContent(name: "Spec")))
        payload.nodes = [t1, t2, t3, n1]

        // 添加 2 条连接
        let conn1 = TerminalConnection(id: UUID(), terminalIdA: t1.id, terminalIdB: t2.id,
                                       ropePoints: Array(repeating: [0.0, 0.0], count: 21))
        let conn2 = TerminalConnection(id: UUID(), terminalIdA: t2.id, terminalIdB: t3.id,
                                       ropePoints: Array(repeating: [0.0, 0.0], count: 21))
        payload.connections = [conn1, conn2]

        let doc = WorkspaceDocument(payload: payload)
        let data = try pm.encoder.encode(doc)
        let decoded = try pm.decoder.decode(WorkspaceDocument.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.type, "workspace")
        XCTAssertEqual(decoded.payload.nodes.count, 4)
        XCTAssertEqual(decoded.payload.connections.count, 2)
        XCTAssertEqual(decoded.payload.name, "FullTest")
        XCTAssertEqual(decoded.payload.workingDirectory, "/projects/test")
    }

    // MARK: - AC6: 与 Maestri 格式兼容（JSON 键名）

    func testJSONKeyNamesAreCamelCase() throws {
        let payload = WorkspacePayload(name: "CamelTest", workingDirectory: "/tmp")
        let doc = WorkspaceDocument(payload: payload)
        let data = try pm.encoder.encode(doc)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // 顶层键
        XCTAssertNotNil(json["schemaVersion"])
        XCTAssertNotNil(json["payload"])
        // payload 内键
        let p = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertNotNil(p["workingDirectory"])
        XCTAssertNotNil(p["noteConnections"])
        XCTAssertNotNil(p["portalConnections"])
        XCTAssertNotNil(p["canvasOrigin"])
        XCTAssertNotNil(p["canvasZoom"])
    }

    // MARK: - 目录创建

    func testEnsureDirectoriesExist() throws {
        try pm.ensureDirectoriesExist()
        XCTAssertTrue(FileManager.default.fileExists(atPath: pm.appDataURL.path))
    }
}
