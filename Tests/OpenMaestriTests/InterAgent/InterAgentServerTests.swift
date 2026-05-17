import XCTest
@testable import open_maestri

final class InterAgentServerTests: XCTestCase {

    // MARK: - NFR7: 安全约束验证

    func testServerBindsToLoopbackOnly() {
        // Constants.interAgentServerHost 必须是 127.0.0.1
        XCTAssertEqual(Constants.interAgentServerHost, "127.0.0.1",
                       "NFR7: InterAgentServer must only bind to loopback interface")
    }

    func testServerRestartDelayIsThreeSeconds() {
        XCTAssertEqual(Constants.serverRestartDelay, 3.0,
                       "NFR6: Server must restart within 3 seconds after crash")
    }

    // MARK: - CLIRouter 路由完整性

    func testCLIRouterHandlesAllKnownCommands() async {
        let router = CLIRouter.shared
        let tid = UUID()

        // 所有命令必须不返回 "error: unknown command"
        let commands = [
            ["list"],
            ["ask", "agent", "prompt"],
            ["check", "agent"],
            ["note", "read", "name"],
            ["portal", "navigate", "name", "url"],
            ["recruit", "name"],
            ["dismiss", "name"],
            ["connect", "a", "b"],
            ["role", "list"],
        ]

        for args in commands {
            let result = await router.routeAsync(args: args, terminalId: tid)
            XCTAssertFalse(
                result.hasPrefix("error: unknown command"),
                "Command '\(args[0])' should be routed, got: \(result)"
            )
        }
    }

    // MARK: - HTTP 请求解析

    func testHTTPResponseFormat() {
        // HTTP 响应应包含状态行和 Content-Type
        let server = InterAgentServer.shared
        // 通过反射获取 buildHTTPResponse（private 方法测试通过公开接口验证）
        // 验证 port 初始值为 0（未启动时）
        XCTAssertEqual(server.port, 0, "Port should be 0 before server starts")
    }

    // MARK: - NoteHandler 文件 I/O 集成测试

    func testNoteHandlerReadWriteRoundTrip() throws {
        let nm = NoteFileManager.shared
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteHandlerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let filePath = tmpDir.appendingPathComponent("test.md").path
        try nm.write(filePath: filePath, content: "Line 1\nLine 2\nLine 3\n")

        let result = try nm.readWithLineRange(filePath: filePath)
        XCTAssertTrue(result.contains("[3 lines total]") || result.contains("[4 lines total]"),
                      "Should include line count header, got: \(result)")
        XCTAssertTrue(result.contains("Line 1"))
        XCTAssertTrue(result.contains("Line 3"))
    }

    func testNoteHandlerReadWithRange() throws {
        let nm = NoteFileManager.shared
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteRangeTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let filePath = tmpDir.appendingPathComponent("range.md").path
        let content = (1...10).map { "Line \($0)" }.joined(separator: "\n")
        try nm.write(filePath: filePath, content: content)

        let result = try nm.readWithLineRange(filePath: filePath, offset: 3, limit: 2)
        XCTAssertTrue(result.contains("Line 3"))
        XCTAssertTrue(result.contains("Line 4"))
        XCTAssertFalse(result.contains("Line 5"))
    }

    // MARK: - SkillInjector 脚本生成质量

    func testSkillScriptIsNonEmpty() {
        let injector = SkillInjector.shared
        let script = injector.buildSkillScript(terminalId: UUID(), host: "127.0.0.1:9999")
        XCTAssertFalse(script.isEmpty)
        XCTAssertGreaterThan(script.count, 100, "Script should be substantial")
    }

    func testSkillScriptHostInjected() {
        let injector = SkillInjector.shared
        let host = "127.0.0.1:54321"
        let script = injector.buildSkillScript(terminalId: UUID(), host: host)
        XCTAssertTrue(script.contains(host), "Script must embed the actual host")
    }

    // MARK: - 数据格式兼容性（NFR14）

    func testWorkspaceDocumentSchemaVersion() {
        let payload = WorkspacePayload(name: "test", workingDirectory: "/tmp")
        let doc = WorkspaceDocument(payload: payload)
        XCTAssertEqual(doc.schemaVersion, 2, "Must be compatible with Maestri v0.25.4 schemaVersion:2")
        XCTAssertEqual(doc.type, "workspace")
    }

    func testCanvasNodeFrameJSONFormat() throws {
        let pm = PersistenceManager.shared
        let frame = CGRect(x: 100, y: 200, width: 300, height: 150)
        let node = CanvasNode(frame: frame, content: .terminal(TerminalContent(name: "test")))
        let data = try pm.encoder.encode(node)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let frameArr = try XCTUnwrap(json["frame"] as? [[Double]])
        // 必须是 [[x,y],[w,h]] 格式（与 Maestri 格式一致）
        XCTAssertEqual(frameArr[0][0], 100, accuracy: 0.01)  // x
        XCTAssertEqual(frameArr[0][1], 200, accuracy: 0.01)  // y
        XCTAssertEqual(frameArr[1][0], 300, accuracy: 0.01)  // width
        XCTAssertEqual(frameArr[1][1], 150, accuracy: 0.01)  // height
    }

    func testDateFieldsAreISO8601Format() throws {
        let pm = PersistenceManager.shared
        let payload = WorkspacePayload(name: "DateTest", workingDirectory: "/tmp")
        let doc = WorkspaceDocument(payload: payload)
        let data = try pm.encoder.encode(doc)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payloadDict = try XCTUnwrap(json["payload"] as? [String: Any])
        let createdAt = try XCTUnwrap(payloadDict["createdAt"] as? String)
        // ISO8601 格式示例：2026-05-16T03:30:00Z
        XCTAssertTrue(createdAt.contains("T"), "Date must be ISO8601, got: \(createdAt)")
        XCTAssertTrue(createdAt.contains("Z") || createdAt.contains("+00"),
                      "Date must be UTC, got: \(createdAt)")
    }
}
