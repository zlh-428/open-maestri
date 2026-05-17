import XCTest
@testable import open_maestri

final class TerminalSessionTests: XCTestCase {

    func testOutputBufferRecordsLines() {
        let session = TerminalSession(id: UUID(), command: "zsh", workingDirectory: "/tmp", roleName: nil)
        session.recordOutput("line1\nline2\nline3")
        let output = session.recentOutput(lines: 10)
        XCTAssertTrue(output.contains("line1"))
        XCTAssertTrue(output.contains("line3"))
    }

    func testRecentOutputLimitsLines() {
        let session = TerminalSession(id: UUID(), command: "zsh", workingDirectory: "/tmp", roleName: nil)
        for i in 1...30 {
            session.recordOutput("line\(i)")
        }
        let recent = session.recentOutput(lines: 5)
        let lines = recent.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertLessThanOrEqual(lines.count, 5)
        // 最后的行应该包含在内
        XCTAssertTrue(recent.contains("line30"))
    }

    func testBufferMaxLinesNotExceeded() {
        let session = TerminalSession(id: UUID(), command: "zsh", workingDirectory: "/tmp", roleName: nil)
        // 写入超过 500 行
        for i in 1...600 {
            session.recordOutput("line\(i)")
        }
        let all = session.recentOutput(lines: 1000)
        let lineCount = all.components(separatedBy: "\n").filter { !$0.isEmpty }.count
        XCTAssertLessThanOrEqual(lineCount, 500)
    }

    func testMarkIdleSetsIdleFlag() {
        let session = TerminalSession(id: UUID(), command: "zsh", workingDirectory: "/tmp", roleName: nil)
        session.recordOutput("some output")
        XCTAssertFalse(session.isIdle)
        session.markIdle()
        XCTAssertTrue(session.isIdle)
    }

    func testWriteCallsOutputCallback() {
        let session = TerminalSession(id: UUID(), command: "zsh", workingDirectory: "/tmp", roleName: nil)
        var received = ""
        session.onOutput = { received = $0 }
        session.write("hello\n")
        XCTAssertEqual(received, "hello\n")
    }

    @MainActor
    func testTerminalManagerCreateAndRemove() {
        let tm = TerminalManager.shared
        let id = UUID()
        let preset = AgentPreset(id: UUID(), name: "Shell", command: "zsh", icon: "terminal.fill", agentType: "generic_shell", color: "#8E8E93", isActive: true, isBuiltIn: true)
        let session = tm.createTerminal(id: id, workingDirectory: "/tmp", preset: preset)

        XCTAssertEqual(session.id, id)
        XCTAssertNotNil(tm.terminals[id])

        tm.removeTerminal(id: id)
        XCTAssertNil(tm.terminals[id])
    }
}
