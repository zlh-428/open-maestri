import XCTest
@testable import open_maestri

/// 测试 AskHandler/CheckHandler 的 Agent 名字匹配逻辑
@MainActor
final class AgentMatchingTests: XCTestCase {
    var tm: TerminalManager!

    override func setUp() async throws {
        tm = TerminalManager.shared
    }

    // MARK: - agentName 匹配

    func testAskHandlerMatchesByAgentName() async {
        // 模拟 Maestro recruit 设置的 agentName
        let recruitId = UUID()
        let preset = AgentPreset.defaults.first { $0.agentType == "claude_code" } ?? AgentPreset.defaults[0]
        let session = tm.createTerminal(id: recruitId, workingDirectory: "/tmp", preset: preset)
        session.agentName = "Builder"  // Maestro 设置的实际名称

        // AskHandler 应能通过 "Builder" 找到终端
        let cm = ConnectionManager.shared
        let callerId = UUID()
        let callerPreset = AgentPreset.defaults.last!
        _ = tm.createTerminal(id: callerId, workingDirectory: "/tmp", preset: callerPreset)
        _ = cm.connectTerminals(idA: callerId, idB: recruitId, serverPort: 0)

        let result = await AskHandler.shared.handleAsync(
            args: ["ask", "Builder", "hello"],
            terminalId: callerId
        )

        // 不应返回 "not found"
        XCTAssertFalse(result.contains("not found"), "agentName='Builder' 应能被找到，实际返回：\(result)")

        // 清理
        cm.disconnectAll(involvedNode: callerId)
        tm.removeTerminal(id: callerId)
        tm.removeTerminal(id: recruitId)
    }

    func testAskHandlerMatchesByCommand() async {
        // 无 agentName 时，通过 command 名称匹配
        let termId = UUID()
        let preset = AgentPreset(id: UUID(), name: "Shell", command: "zsh", icon: "terminal",
                                 agentType: "generic_shell", color: "#8E8E93", isActive: true, isBuiltIn: true)
        _ = tm.createTerminal(id: termId, workingDirectory: "/tmp", preset: preset)

        let callerId = UUID()
        let callerPreset = AgentPreset.defaults.last!
        _ = tm.createTerminal(id: callerId, workingDirectory: "/tmp", preset: callerPreset)
        let cm = ConnectionManager.shared
        _ = cm.connectTerminals(idA: callerId, idB: termId, serverPort: 0)

        let result = await AskHandler.shared.handleAsync(
            args: ["ask", "zsh", "hello"],
            terminalId: callerId
        )
        XCTAssertFalse(result.contains("not found"),
                       "command='zsh' 应能被找到，实际：\(result)")

        cm.disconnectAll(involvedNode: callerId)
        tm.removeTerminal(id: callerId)
        tm.removeTerminal(id: termId)
    }

    func testAskHandlerReturnsNotFoundForUnknownName() async {
        let callerId = UUID()
        let preset = AgentPreset.defaults.last!
        _ = tm.createTerminal(id: callerId, workingDirectory: "/tmp", preset: preset)

        let result = await AskHandler.shared.handleAsync(
            args: ["ask", "NonExistentAgent99", "hello"],
            terminalId: callerId
        )
        XCTAssertTrue(result.contains("not found"),
                      "未知 agent 应返回 not found，实际：\(result)")

        tm.removeTerminal(id: callerId)
    }
}
