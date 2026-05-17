import XCTest
import CoreGraphics
@testable import open_maestri

@MainActor
final class CanvasNodeRendererTests: XCTestCase {

    // MARK: - 辅助

    private func makeCanvas() -> CanvasViewportView {
        let view = CanvasViewportView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
        return view
    }

    private func makeWorkspace(name: String = "Test") -> WorkspaceManager {
        WorkspaceManager(id: UUID(), name: name, workingDirectory: "/tmp/test")
    }

    private func makeTerminalNode(at origin: CGPoint = .zero) -> CanvasNode {
        let tc = TerminalContent(name: "Claude", agentType: "claude_code", command: "claude")
        return CanvasNode(
            frame: CGRect(origin: origin, size: CGSize(width: 600, height: 400)),
            content: .terminal(tc)
        )
    }

    private func makeNoteNode() -> CanvasNode {
        let nc = StickyNoteContent(name: "Note-1")
        return CanvasNode(
            frame: CGRect(x: 100, y: 100, width: 260, height: 200),
            content: .stickyNote(nc)
        )
    }

    // MARK: - 增量同步

    func testSyncAddsNewNode() {
        let canvas = makeCanvas()
        let ws = makeWorkspace()
        let renderer = CanvasNodeRenderer(canvas: canvas)

        let node = makeTerminalNode()
        ws.addNode(node)
        renderer.sync(nodes: ws.nodes, workspace: ws)

        XCTAssertEqual(canvas.subviews.filter { $0 is TerminalNodeView }.count, 1,
                       "一个 Terminal 节点应产生一个 TerminalNodeView")
    }

    func testSyncRemovesDeletedNode() {
        let canvas = makeCanvas()
        let ws = makeWorkspace()
        let renderer = CanvasNodeRenderer(canvas: canvas)

        let node = makeTerminalNode()
        ws.addNode(node)
        renderer.sync(nodes: ws.nodes, workspace: ws)
        XCTAssertEqual(canvas.subviews.filter { $0 is TerminalNodeView }.count, 1)

        ws.removeNode(id: node.id)
        renderer.sync(nodes: ws.nodes, workspace: ws)
        XCTAssertEqual(canvas.subviews.filter { $0 is TerminalNodeView }.count, 0,
                       "删除节点后 TerminalNodeView 应从画布移除")
    }

    func testSyncIsIdempotent() {
        let canvas = makeCanvas()
        let ws = makeWorkspace()
        let renderer = CanvasNodeRenderer(canvas: canvas)

        let node = makeTerminalNode()
        ws.addNode(node)
        renderer.sync(nodes: ws.nodes, workspace: ws)
        renderer.sync(nodes: ws.nodes, workspace: ws)
        renderer.sync(nodes: ws.nodes, workspace: ws)

        XCTAssertEqual(canvas.subviews.filter { $0 is TerminalNodeView }.count, 1,
                       "重复 sync 不应创建重复节点视图")
    }

    func testSyncMultipleNodeTypes() {
        let canvas = makeCanvas()
        let ws = makeWorkspace()
        let renderer = CanvasNodeRenderer(canvas: canvas)

        ws.addNode(makeTerminalNode(at: CGPoint(x: 100, y: 100)))
        ws.addNode(makeNoteNode())
        renderer.sync(nodes: ws.nodes, workspace: ws)

        let termCount = canvas.subviews.filter { $0 is TerminalNodeView }.count
        let noteCount = canvas.subviews.filter { $0 is NoteNodeView }.count
        XCTAssertEqual(termCount, 1)
        XCTAssertEqual(noteCount, 1)
    }

    // MARK: - 拖拽回写

    func testOnFrameChangedUpdatesWorkspaceNode() {
        let canvas = makeCanvas()
        let ws = makeWorkspace()
        let renderer = CanvasNodeRenderer(canvas: canvas)

        let node = makeTerminalNode(at: CGPoint(x: 9800, y: 8500))
        ws.addNode(node)
        renderer.sync(nodes: ws.nodes, workspace: ws)

        guard let termView = canvas.subviews.first(where: { $0 is TerminalNodeView }) as? TerminalNodeView else {
            XCTFail("TerminalNodeView not found"); return
        }

        // 模拟拖拽：在屏幕坐标中移动，触发 onFrameChanged
        let newScreenFrame = CGRect(x: 50, y: 50, width: 600, height: 400)
        termView.onFrameChanged?(newScreenFrame)

        // 等待 Task 执行
        let expectation = XCTestExpectation(description: "frame updated")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertNotNil(ws.nodes.first { $0.id == node.id }, "节点仍应存在于 workspace")
    }

    // MARK: - 连线渲染

    func testSyncConnectionsRendersTerminalConnection() {
        let canvas = makeCanvas()
        let ws = makeWorkspace()
        let renderer = CanvasNodeRenderer(canvas: canvas)

        let nodeA = makeTerminalNode(at: CGPoint(x: 9800, y: 8500))
        let nodeB = makeTerminalNode(at: CGPoint(x: 10500, y: 8500))
        ws.addNode(nodeA); ws.addNode(nodeB)
        renderer.sync(nodes: ws.nodes, workspace: ws)

        let conn = TerminalConnection(terminalIdA: nodeA.id, terminalIdB: nodeB.id)
        ws.addConnection(conn)
        renderer.syncConnections(workspace: ws)

        let overlay = canvas.subviews.first { $0 is ConnectionOverlayView } as? ConnectionOverlayView
        XCTAssertNotNil(overlay, "ConnectionOverlayView 应存在于画布")
        XCTAssertEqual(overlay?.connections.count, 1, "应渲染 1 条连线")
    }

    func testSyncConnectionsRendersNoteToNoteConnection() {
        let canvas = makeCanvas()
        let ws = makeWorkspace()
        let renderer = CanvasNodeRenderer(canvas: canvas)

        let noteA = makeNoteNode()
        var noteB = makeNoteNode()
        noteB = CanvasNode(
            frame: CGRect(x: 400, y: 100, width: 260, height: 200),
            content: noteB.content
        )
        ws.addNode(noteA); ws.addNode(noteB)
        renderer.sync(nodes: ws.nodes, workspace: ws)

        ws.noteToNoteConnections.append(NoteToNoteConnection(noteNodeIdA: noteA.id, noteNodeIdB: noteB.id))
        renderer.syncConnections(workspace: ws)

        let overlay = canvas.subviews.first { $0 is ConnectionOverlayView } as? ConnectionOverlayView
        XCTAssertEqual(overlay?.connections.count, 1, "Note↔Note 连线应被渲染")
    }
}
