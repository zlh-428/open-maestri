import AppKit
import SwiftUI
import SwiftTerm
import OSLog

/// 画布节点渲染引擎
/// 使用单个 CanvasNodesView（NSHostingView）渲染所有节点，无 per-node NSView 管理
@MainActor
final class CanvasNodeRenderer {
    private let logger = Logger.make(category: "CanvasNodeRenderer")
    private weak var canvas: CanvasViewportView?
    /// 当前工作区（供节点回调使用）
    private weak var currentWorkspace: WorkspaceManager?
    private var notificationObservers: [NSObjectProtocol] = []
    /// 当前可用角色列表（由外部在 sync 前注入）
    var rolePresets: [RolePreset] = []

    /// 节点 SwiftUI 容器（单一 HostingView）
    private var nodesHostingView: CanvasNodesView?

    // 连线层
    private(set) var overlayView: ConnectionOverlayView?

    init(canvas: CanvasViewportView) {
        self.canvas = canvas
        setupNodesHostingView(canvas: canvas)
        setupOverlay(canvas: canvas)
        setupNodeDragCallback(canvas: canvas)
        setupActivationObserver()
        setupSelectionObserver()
    }

    private func setupNodesHostingView(canvas: CanvasViewportView) {
        let rootView = CanvasNodesSwiftUIView(
            nodes: [],
            canvasOrigin: canvas.canvasOrigin,
            zoom: canvas.zoom,
            selectedNodeIds: [],
            lockedNodeIds: [],
            workspace: nil
        )
        let hostingView = CanvasNodesView(rootView: rootView)
        hostingView.frame = canvas.bounds
        hostingView.autoresizingMask = [.width, .height]
        canvas.addSubview(hostingView)
        nodesHostingView = hostingView
        canvas.nodesHostingView = hostingView
    }

    private func setupNodeDragCallback(canvas: CanvasViewportView) {
        canvas.onNodeDragEnded = { [weak self] nodeId, canvasFrame in
            guard let self else { return }
            self.currentWorkspace?.updateNodeFrame(id: nodeId, frame: canvasFrame)
            self.saveWorkspace()
        }
        canvas.onBatchNodeDragEnded = { [weak self] finalFrames in
            guard let self else { return }
            for (nodeId, frame) in finalFrames {
                self.currentWorkspace?.updateNodeFrame(id: nodeId, frame: frame)
            }
            self.saveWorkspace()
        }
        // Resize 结束：持久化新 frame
        canvas.onNodeResizeEnded = { [weak self] nodeId, canvasFrame in
            guard let self else { return }
            self.currentWorkspace?.updateNodeFrame(id: nodeId, frame: canvasFrame)
            self.saveWorkspace()
        }
        canvas.onDuplicateNode = { [weak self] id in
            self?.handleDuplicate(id: id)
        }
    }

    private func saveWorkspace() {
        guard let ws = currentWorkspace else { return }
        Task {
            do {
                try await ws.save()
            } catch {
                logger.error("Failed to save workspace: \(error.localizedDescription)")
            }
        }
    }

    private func setupOverlay(canvas: CanvasViewportView) {
        let overlay = ConnectionOverlayView(frame: canvas.bounds)
        overlay.autoresizingMask = [.width, .height]
        canvas.addSubview(overlay)
        overlayView = overlay

        // 连线右键删除回调
        overlay.onDeleteConnection = { [weak self] connectionId in
            guard let self, let ws = self.currentWorkspace else { return }
            // 从所有连接类型中查找并删除
            ws.connections.removeAll { $0.id == connectionId }
            ws.noteConnections.removeAll { $0.id == connectionId }
            ws.portalConnections.removeAll { $0.id == connectionId }
            ws.portalToPortalConnections.removeAll { $0.id == connectionId }
            ws.noteToNoteConnections.removeAll { $0.id == connectionId }
            ConnectionManager.shared.disconnect(id: connectionId)
            overlay.removeConnection(id: connectionId)
            self.saveWorkspace()
            self.logger.info("Connection \(connectionId.uuidString.prefix(8)) deleted via context menu")
        }
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - 同步节点列表

    /// 使用单个 HostingView 全量替换节点渲染
    func sync(nodes: [CanvasNode], workspace: WorkspaceManager) {
        guard let canvas else { return }
        currentWorkspace = workspace

        let lockedIds = Set(nodes.filter { $0.isLocked }.map { $0.id })

        nodesHostingView?.rootView = CanvasNodesSwiftUIView(
            nodes: nodes,
            canvasOrigin: canvas.canvasOrigin,
            zoom: canvas.zoom,
            selectedNodeIds: canvas.selectedNodeIds,
            lockedNodeIds: lockedIds,
            workspace: workspace,
            onActivated: { [weak canvas] id in
                guard let canvas else { return }
                if let provider = TerminalProviderRegistry.shared.provider(for: id),
                   let tv = provider.terminalView {
                    tv.window?.makeFirstResponder(tv)
                }
                canvas.selectedNodeIds = [id]
            },
            onClose: { [weak self] id in
                self?.removeNode(id: id, from: self?.currentWorkspace)
            },
            onRename: { [weak self] id, newName in
                self?.handleRename(id: id, newName: newName)
            },
            onDuplicate: { [weak self] id in
                self?.handleDuplicate(id: id)
            },
            onLockToggle: { [weak self] id, locked in
                self?.handleLockToggle(id: id, locked: locked)
            }
        )

        for node in nodes {
            canvas.nodeCanvasFrames[node.id] = node.frame
        }
        canvas.currentNodes = nodes

        if let overlay = overlayView {
            canvas.addSubview(overlay)
        }
    }

    // MARK: - 节点删除

    func removeNode(id: UUID, from workspace: WorkspaceManager?) {
        // Note 节点删除时同时删除磁盘 .md 文件（官方行为：docs/05-notes.md）
        if let (nc, wsId) = noteInfo(nodeId: id, workspace: workspace) {
            switch nc.storageMode {
            case .managed:
                if let fn = nc.fileName, let ws = workspace {
                    let path = PersistenceManager.shared.notesDirURL(workspaceId: ws.id)
                        .appendingPathComponent(fn).path
                    do {
                        try FileManager.default.removeItem(atPath: path)
                    } catch {
                        logger.error("Failed to delete note file at \(path): \(error.localizedDescription)")
                    }
                }
            case .custom(let customPath):
                // custom 路径由用户管理，不自动删除（与官方行为一致）
                logger.debug("Custom note at \(customPath) not deleted (user-managed)")
            }
            _ = wsId
        }

        NoteRegistry.shared.unregisterByNodeId(id)
        ConnectionManager.shared.disconnectAll(involvedNode: id)
        workspace?.removeNode(id: id)
    }

    private func noteInfo(nodeId: UUID, workspace: WorkspaceManager?) -> (StickyNoteContent, UUID)? {
        guard let ws = workspace,
              let node = ws.nodes.first(where: { $0.id == nodeId }),
              case .stickyNote(let nc) = node.content else { return nil }
        return (nc, ws.id)
    }

    // MARK: - 节点操作回调

    private func handleRename(id: UUID, newName: String) {
        guard let ws = currentWorkspace,
              let idx = ws.nodes.firstIndex(where: { $0.id == id }) else { return }
        switch ws.nodes[idx].content {
        case .terminal(var tc):
            tc.name = newName
            ws.nodes[idx].content = .terminal(tc)
        case .stickyNote(var nc):
            nc.hasCustomName = true
            nc.fileName = newName.hasSuffix(".md") ? newName : "\(newName).md"
            ws.nodes[idx].content = .stickyNote(nc)
        case .portal(var pc):
            pc.name = newName
            ws.nodes[idx].content = .portal(pc)
        case .fileTree(var fc):
            fc.name = newName
            ws.nodes[idx].content = .fileTree(fc)
        default:
            break
        }
        saveWorkspace()
    }

    private func handleDuplicate(id: UUID) {
        guard let ws = currentWorkspace,
              let original = ws.nodes.first(where: { $0.id == id }) else { return }
        var copy = original
        copy.id = UUID()
        copy.frame = copy.frame.offsetBy(dx: 30, dy: 30)
        copy.zIndex = (ws.nodes.map { $0.zIndex }.max() ?? 0) + 1
        // 对 Terminal 内容生成新 ID
        if case .terminal(var tc) = copy.content {
            tc.id = UUID()
            copy.content = .terminal(tc)
        }
        ws.addNode(copy)
        saveWorkspace()
    }

    private func handleLockToggle(id: UUID, locked: Bool) {
        guard let ws = currentWorkspace,
              let idx = ws.nodes.firstIndex(where: { $0.id == id }) else { return }
        ws.nodes[idx].isLocked = locked
        saveWorkspace()
    }

    // MARK: - 通知观察者

    private func setupActivationObserver() {
        let obs = NotificationCenter.default.addObserver(
            forName: .canvasNodeActivated, object: nil, queue: .main
        ) { [weak self] notif in
            guard let id = notif.userInfo?["nodeId"] as? UUID else { return }
            if let provider = TerminalProviderRegistry.shared.provider(for: id),
               let tv = provider.terminalView {
                tv.window?.makeFirstResponder(tv)
            }
        }
        notificationObservers.append(obs)
    }

    private func setupSelectionObserver() {
        let obs = NotificationCenter.default.addObserver(
            forName: .canvasSelectionChanged, object: nil, queue: .main
        ) { [weak self] notif in
            guard let self,
                  let canvas = self.canvas,
                  let ws = self.currentWorkspace,
                  let ids = notif.userInfo?["selectedIds"] as? Set<UUID> else { return }
            let lockedIds = Set(ws.nodes.filter { $0.isLocked }.map { $0.id })
            let current = self.nodesHostingView?.rootView
            self.nodesHostingView?.rootView = CanvasNodesSwiftUIView(
                nodes: ws.nodes,
                canvasOrigin: canvas.canvasOrigin,
                zoom: canvas.zoom,
                selectedNodeIds: ids,
                lockedNodeIds: lockedIds,
                workspace: ws,
                onActivated: current?.onActivated,
                onClose: current?.onClose,
                onRename: current?.onRename,
                onDuplicate: current?.onDuplicate,
                onLockToggle: current?.onLockToggle
            )
        }
        notificationObservers.append(obs)
    }

    // MARK: - 连线同步

    func syncConnections(workspace: WorkspaceManager) {
        guard let overlay = overlayView, let canvas else { return }

        var renderables: [RenderableConnection] = []

        for conn in workspace.connections {
            guard let frameA = nodeFrame(id: conn.terminalIdA, in: workspace),
                  let frameB = nodeFrame(id: conn.terminalIdB, in: workspace) else { continue }
            let points = computeRopeScreenPoints(frameA: frameA, frameB: frameB, canvas: canvas)
            let status = ConnectionManager.shared.connections.values
                .first { $0.nodeIdA == conn.terminalIdA && $0.nodeIdB == conn.terminalIdB }?.status ?? .idle
            renderables.append(RenderableConnection(id: conn.id, screenPoints: points, status: status))
        }

        for conn in workspace.noteConnections {
            guard let frameA = nodeFrame(id: conn.terminalId, in: workspace),
                  let frameB = nodeFrame(id: conn.noteNodeId, in: workspace) else { continue }
            let points = computeRopeScreenPoints(frameA: frameA, frameB: frameB, canvas: canvas)
            renderables.append(RenderableConnection(id: conn.id, screenPoints: points, status: .idle))
        }

        for conn in workspace.portalConnections {
            guard let frameA = nodeFrame(id: conn.terminalId, in: workspace),
                  let frameB = nodeFrame(id: conn.portalNodeId, in: workspace) else { continue }
            let points = computeRopeScreenPoints(frameA: frameA, frameB: frameB, canvas: canvas)
            renderables.append(RenderableConnection(id: conn.id, screenPoints: points, status: .idle))
        }

        // Note↔Note 连接（Note Chaining）
        for conn in workspace.noteToNoteConnections {
            guard let frameA = nodeFrame(id: conn.noteNodeIdA, in: workspace),
                  let frameB = nodeFrame(id: conn.noteNodeIdB, in: workspace) else { continue }
            let points = computeRopeScreenPoints(frameA: frameA, frameB: frameB, canvas: canvas)
            renderables.append(RenderableConnection(id: conn.id, screenPoints: points, status: .idle))
        }

        // Portal↔Portal 连接（共享 session）
        for conn in workspace.portalToPortalConnections {
            guard let frameA = nodeFrame(id: conn.portalIdA, in: workspace),
                  let frameB = nodeFrame(id: conn.portalIdB, in: workspace) else { continue }
            let points = computeRopeScreenPoints(frameA: frameA, frameB: frameB, canvas: canvas)
            renderables.append(RenderableConnection(id: conn.id, screenPoints: points, status: .idle))
        }

        overlay.connections = renderables
    }

    private func nodeFrame(id: UUID, in workspace: WorkspaceManager) -> CGRect? {
        workspace.nodes.first { $0.id == id }?.frame
    }

    private func computeRopeScreenPoints(frameA: CGRect, frameB: CGRect, canvas: CanvasViewportView) -> [CGPoint] {
        // 节点 frame origin 是画布坐标，宽高是画布原始尺寸（不含 zoom）
        // 屏幕中点 = canvasToScreen(origin) + 宽高/2 * zoom
        let screenOriginA = canvas.canvasToScreen(frameA.origin)
        let screenOriginB = canvas.canvasToScreen(frameB.origin)
        let startScreen = CGPoint(
            x: screenOriginA.x + frameA.width * canvas.zoom / 2,
            y: screenOriginA.y + frameA.height * canvas.zoom / 2
        )
        let endScreen = CGPoint(
            x: screenOriginB.x + frameB.width * canvas.zoom / 2,
            y: screenOriginB.y + frameB.height * canvas.zoom / 2
        )
        let rope = RopeSimulation()
        return rope.compute(from: startScreen, to: endScreen)
    }
}
