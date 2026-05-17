import XCTest
import CoreGraphics
@testable import open_maestri

// Story 1.2 AC: frame [[x,y],[w,h]] 格式兼容性测试（NFR14: 与 Maestri v0.25.4 兼容）
final class CGRectFrameTests: XCTestCase {

    // MARK: - CGRect+Frame 扩展

    func testFrameArrayEncoding() {
        let rect = CGRect(x: 100, y: 200, width: 300, height: 400)
        let arr = rect.frameArray
        XCTAssertEqual(arr.count, 2)
        XCTAssertEqual(arr[0].count, 2)
        XCTAssertEqual(arr[1].count, 2)
        XCTAssertEqual(arr[0][0], 100.0) // x
        XCTAssertEqual(arr[0][1], 200.0) // y
        XCTAssertEqual(arr[1][0], 300.0) // width
        XCTAssertEqual(arr[1][1], 400.0) // height
    }

    func testFrameArrayDecoding() {
        let arr: [[Double]] = [[50.0, 75.0], [200.0, 150.0]]
        let rect = CGRect(frameArray: arr)
        XCTAssertNotNil(rect)
        XCTAssertEqual(rect?.origin.x ?? 0, 50, accuracy: 0.01)
        XCTAssertEqual(rect?.origin.y ?? 0, 75, accuracy: 0.01)
        XCTAssertEqual(rect?.size.width ?? 0, 200, accuracy: 0.01)
        XCTAssertEqual(rect?.size.height ?? 0, 150, accuracy: 0.01)
    }

    func testInvalidFrameArrayReturnsNil() {
        XCTAssertNil(CGRect(frameArray: [[100.0]]))         // 只有 1 个子数组
        XCTAssertNil(CGRect(frameArray: [[100.0], [200.0]])) // 子数组元素不足
        XCTAssertNil(CGRect(frameArray: []))                 // 空数组
    }

    func testFrameRoundTrip() {
        let original = CGRect(x: 9800, y: 8500, width: 400, height: 300)
        let arr = original.frameArray
        let restored = CGRect(frameArray: arr)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.origin.x ?? 0, original.origin.x, accuracy: 0.001)
        XCTAssertEqual(restored?.origin.y ?? 0, original.origin.y, accuracy: 0.001)
        XCTAssertEqual(restored?.size.width ?? 0, original.size.width, accuracy: 0.001)
        XCTAssertEqual(restored?.size.height ?? 0, original.size.height, accuracy: 0.001)
    }

    // MARK: - CanvasNode 序列化（NFR14 关键）

    func testCanvasNodeFrameIsArrayOfArraysInJSON() throws {
        let pm = PersistenceManager.shared
        let node = CanvasNode(
            frame: CGRect(x: 9900, y: 8600, width: 400, height: 300),
            content: .terminal(TerminalContent(name: "Claude"))
        )
        let data = try pm.encoder.encode(node)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // frame 必须是 [[x,y],[w,h]] 而非 {x:..., y:..., width:..., height:...}
        let frame = try XCTUnwrap(json["frame"] as? [[Double]],
                                   "frame must be [[Double]] format, got: \(json["frame"] as Any)")
        XCTAssertEqual(frame.count, 2)
        XCTAssertEqual(frame[0].count, 2)
        XCTAssertEqual(frame[1].count, 2)
    }

    // MARK: - NodeContent Maestri 格式（{ "terminal": { "_0": {...} } }）

    func testCanvasNodeFrameDecodeFromMaestriFormat() throws {
        // Maestri v0.25.4 真实格式：content 使用 { "terminal": { "_0": {...} } }
        let maestriJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "frame": [[100.0, 200.0], [400.0, 300.0]],
          "content": {
            "terminal": {
              "_0": {
                "agentType": "claude_code",
                "command": "claude",
                "name": "Agent",
                "icon": "seal",
                "color": "#007AFF",
                "id": "00000000-0000-0000-0000-000000000002",
                "shellPath": "/bin/zsh",
                "workingDirectory": "/tmp",
                "status": "idle",
                "isManager": false,
                "monitorWithOmbro": false,
                "autoScrollLocked": false,
                "shortcutMode": {"kind": "automatic"},
                "scrollbackLineCount": 0
              }
            }
          },
          "zIndex": 0,
          "isLocked": false,
          "createdAt": "2026-05-16T00:00:00Z",
          "lastModifiedAt": "2026-05-16T00:00:00Z"
        }
        """.data(using: .utf8)!
        let node = try PersistenceManager.shared.decoder.decode(CanvasNode.self, from: maestriJSON)
        XCTAssertEqual(node.frame.origin.x, 100, accuracy: 0.01)
        XCTAssertEqual(node.frame.origin.y, 200, accuracy: 0.01)
        XCTAssertEqual(node.frame.size.width, 400, accuracy: 0.01)
        XCTAssertEqual(node.frame.size.height, 300, accuracy: 0.01)
        if case .terminal(let tc) = node.content {
            XCTAssertEqual(tc.agentType, "claude_code")
            XCTAssertEqual(tc.name, "Agent")
        } else {
            XCTFail("Expected terminal content")
        }
    }

    func testTerminalContentEncodesAsMaestriFormat() throws {
        let content = NodeContent.terminal(TerminalContent(name: "test"))
        let data = try PersistenceManager.shared.encoder.encode(content)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // Maestri 格式：顶层 key 为 "terminal"，内部为 "_0"
        XCTAssertNotNil(json["terminal"] as? [String: Any],
                        "NodeContent.terminal must encode as { 'terminal': { '_0': ... } }")
        let inner = try XCTUnwrap(json["terminal"] as? [String: Any])
        XCTAssertNotNil(inner["_0"], "Inner value must be under '_0' key")
    }

    func testAllNodeContentTypesUseMaestriFormat() throws {
        let pm = PersistenceManager.shared
        let cases: [(NodeContent, String)] = [
            (.terminal(TerminalContent(name: "t")),        "terminal"),
            (.stickyNote(StickyNoteContent(name: "n")),    "stickyNote"),
            (.portal(PortalContent(name: "p")),            "portal"),
            (.fileTree(FileTreeContent(name: "f", rootPath: "/tmp")), "fileTree"),
        ]

        for (content, expectedKey) in cases {
            let data = try pm.encoder.encode(content)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNotNil(json[expectedKey],
                            "NodeContent.\(expectedKey) must encode with top-level key '\(expectedKey)'")
        }
    }

    func testNodeContentRoundTripAllTypes() throws {
        let pm = PersistenceManager.shared
        let original: [NodeContent] = [
            .terminal(TerminalContent(name: "Agent1", agentType: "claude_code")),
            .stickyNote(StickyNoteContent(name: "Spec")),
            .portal(PortalContent(name: "Browser", url: "https://example.com")),
            .fileTree(FileTreeContent(name: "Files", rootPath: "/projects")),
        ]

        for content in original {
            let data = try pm.encoder.encode(content)
            let decoded = try pm.decoder.decode(NodeContent.self, from: data)
            let reEncoded = try pm.encoder.encode(decoded)
            XCTAssertEqual(data, reEncoded, "NodeContent round-trip must be idempotent")
        }
    }
}
