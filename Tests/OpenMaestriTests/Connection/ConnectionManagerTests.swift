import XCTest
@testable import open_maestri

@MainActor
final class ConnectionManagerTests: XCTestCase {
    var cm: ConnectionManager!
    var tm: TerminalManager!

    override func setUp() async throws {
        cm = ConnectionManager.shared
        tm = TerminalManager.shared
    }

    // MARK: - 连接建立

    func testConnectTerminalsCreatesConnection() async {
        let idA = UUID()
        let idB = UUID()
        let preset = AgentPreset(id: UUID(), name: "Shell", command: "zsh", icon: "terminal.fill", agentType: "generic_shell", color: "#8E8E93", isActive: true, isBuiltIn: true)
        _ = tm.createTerminal(id: idA, workingDirectory: "/tmp", preset: preset)
        _ = tm.createTerminal(id: idB, workingDirectory: "/tmp", preset: preset)

        let conn = cm.connectTerminals(idA: idA, idB: idB, serverPort: 0)

        XCTAssertEqual(conn.terminalIdA, idA)
        XCTAssertEqual(conn.terminalIdB, idB)
        XCTAssertNotNil(cm.connections[conn.id])
        XCTAssertEqual(cm.connections[conn.id]?.type, .terminalToTerminal)

        // 清理
        cm.disconnect(id: conn.id)
        tm.removeTerminal(id: idA)
        tm.removeTerminal(id: idB)
    }

    func testConnectTerminalToNote() async {
        let termId = UUID()
        let noteId = UUID()
        let preset = AgentPreset.defaults[0]
        _ = tm.createTerminal(id: termId, workingDirectory: "/tmp", preset: preset)

        let conn = cm.connectTerminalToNote(terminalId: termId, noteNodeId: noteId)

        XCTAssertEqual(conn.terminalId, termId)
        XCTAssertEqual(conn.noteNodeId, noteId)
        XCTAssertEqual(cm.connections[conn.id]?.type, .terminalToNote)

        cm.disconnect(id: conn.id)
        tm.removeTerminal(id: termId)
    }

    func testDisconnectRemovesConnection() async {
        let idA = UUID()
        let idB = UUID()
        let preset = AgentPreset.defaults.last!
        _ = tm.createTerminal(id: idA, workingDirectory: "/tmp", preset: preset)
        _ = tm.createTerminal(id: idB, workingDirectory: "/tmp", preset: preset)

        let conn = cm.connectTerminals(idA: idA, idB: idB, serverPort: 0)
        XCTAssertNotNil(cm.connections[conn.id])

        cm.disconnect(id: conn.id)
        XCTAssertNil(cm.connections[conn.id])

        tm.removeTerminal(id: idA)
        tm.removeTerminal(id: idB)
    }

    func testDisconnectAllRemovesAllConnectionsForNode() async {
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()
        let preset = AgentPreset.defaults[0]
        _ = tm.createTerminal(id: idA, workingDirectory: "/tmp", preset: preset)
        _ = tm.createTerminal(id: idB, workingDirectory: "/tmp", preset: preset)
        _ = tm.createTerminal(id: idC, workingDirectory: "/tmp", preset: preset)

        let connAB = cm.connectTerminals(idA: idA, idB: idB, serverPort: 0)
        let connAC = cm.connectTerminals(idA: idA, idB: idC, serverPort: 0)

        cm.disconnectAll(involvedNode: idA)

        XCTAssertNil(cm.connections[connAB.id])
        XCTAssertNil(cm.connections[connAC.id])

        tm.removeTerminal(id: idA)
        tm.removeTerminal(id: idB)
        tm.removeTerminal(id: idC)
    }

    // MARK: - 状态管理

    func testConnectionStatusDefaultIsIdle() async {
        let idA = UUID()
        let idB = UUID()
        let preset = AgentPreset.defaults[0]
        _ = tm.createTerminal(id: idA, workingDirectory: "/tmp", preset: preset)
        _ = tm.createTerminal(id: idB, workingDirectory: "/tmp", preset: preset)

        let conn = cm.connectTerminals(idA: idA, idB: idB, serverPort: 0)
        XCTAssertEqual(cm.connections[conn.id]?.status, .idle)

        cm.disconnect(id: conn.id)
        tm.removeTerminal(id: idA)
        tm.removeTerminal(id: idB)
    }

    func testUpdateStatusChangesConnectionStatus() async {
        let idA = UUID()
        let idB = UUID()
        let preset = AgentPreset.defaults[0]
        _ = tm.createTerminal(id: idA, workingDirectory: "/tmp", preset: preset)
        _ = tm.createTerminal(id: idB, workingDirectory: "/tmp", preset: preset)

        let conn = cm.connectTerminals(idA: idA, idB: idB, serverPort: 0)
        cm.updateStatus(.communicating, for: conn.id)
        XCTAssertEqual(cm.connections[conn.id]?.status, .communicating)

        cm.updateStatus(.disconnected, for: conn.id)
        XCTAssertEqual(cm.connections[conn.id]?.status, .disconnected)

        cm.disconnect(id: conn.id)
        tm.removeTerminal(id: idA)
        tm.removeTerminal(id: idB)
    }

    // MARK: - 查询

    func testConnectionsForNodeReturnsCorrectConnections() async {
        let idA = UUID()
        let idB = UUID()
        let preset = AgentPreset.defaults[0]
        _ = tm.createTerminal(id: idA, workingDirectory: "/tmp", preset: preset)
        _ = tm.createTerminal(id: idB, workingDirectory: "/tmp", preset: preset)

        let conn = cm.connectTerminals(idA: idA, idB: idB, serverPort: 0)
        let connsForA = cm.connections(for: idA)

        XCTAssertTrue(connsForA.contains { $0.id == conn.id })

        cm.disconnect(id: conn.id)
        tm.removeTerminal(id: idA)
        tm.removeTerminal(id: idB)
    }

    func testConnectedNodeIdsReturnsOtherNodeId() async {
        let idA = UUID()
        let idB = UUID()
        let preset = AgentPreset.defaults[0]
        _ = tm.createTerminal(id: idA, workingDirectory: "/tmp", preset: preset)
        _ = tm.createTerminal(id: idB, workingDirectory: "/tmp", preset: preset)

        let conn = cm.connectTerminals(idA: idA, idB: idB, serverPort: 0)
        let connectedToA = cm.connectedNodeIds(for: idA)
        XCTAssertTrue(connectedToA.contains(idB))

        cm.disconnect(id: conn.id)
        tm.removeTerminal(id: idA)
        tm.removeTerminal(id: idB)
    }
}
