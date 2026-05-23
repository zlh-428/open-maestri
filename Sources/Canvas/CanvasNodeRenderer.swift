import AppKit
import SwiftUI
import SwiftTerm
import OSLog

/// 画布节点渲染引擎
/// 使用单个 CanvasNodesView（NSHostingView）渲染所有节点，无 per-node NSView 管理
@MainActor
final class CanvasNodeRenderer {
    let logger = Logger.make(category: "CanvasNodeRenderer")
    weak var canvas: CanvasViewportView?
    /// 当前工作区（供节点回调使用）
    weak var currentWorkspace: WorkspaceManager?
    var notificationObservers: [NSObjectProtocol] = []
    /// 当前可用角色列表（由外部在 sync 前注入）
    var rolePresets: [RolePreset] = []

    /// 节点 SwiftUI 容器（单一 HostingView）
    var nodesHostingView: CanvasNodesView?

    // 连线层
    private(set) var overlayView: ConnectionOverlayView?

    /// 复用的悬链线计算器（避免每条连线每帧都 alloc 新实例）
    let ropeSimulation = RopeSimulation()

    // MARK: - 连线物理状态（由 CanvasNodeRenderer+Physics.swift 管理）

    /// 连接元数据（用于渲染时查找 status）
    struct ConnectionMeta {
        let id: UUID
        let nodeIdA: UUID
        let nodeIdB: UUID
    }

    /// 当前活跃的连接元数据列表（在 syncConnections 中构建）
    var activeConnections: [ConnectionMeta] = []

    /// 连接状态缓存（避免每条连线每帧 O(n) 查找）
    var connectionStatusCache: [UUID: ConnectionStatus] = [:]

    init(canvas: CanvasViewportView) {
        self.canvas = canvas
        setupNodesHostingView(canvas: canvas)
        setupOverlay(canvas: canvas)
        setupDrawingOverlay(canvas: canvas)
        setupNodeDragCallback(canvas: canvas)
        setupActivationObserver()
        setupSelectionObserver()
        setupDropTargetObserver()
        setupNodeStateObservers()
        setupPhysicsCallbacks()
        // 画布 pan/zoom 变化时直接刷新连线屏幕坐标（绕过 SwiftUI 时序问题）
        canvas.onViewportPanned = { [weak self] in
            self?.rerenderConnections()
            self?.canvas?.syncTemporaryConnectionToOverlay()
        }
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
        // 禁止 NSHostingView 向 SwiftUI 传播 safe area insets，
        // 确保 GeometryReader 尺寸与 NSHostingView frame 完全一致（修复 hitTest 坐标偏移）
        hostingView.safeAreaRegions = []
        hostingView.frame = canvas.bounds
        hostingView.autoresizingMask = [.width, .height]
        canvas.addSubview(hostingView)
        nodesHostingView = hostingView
        canvas.nodesHostingView = hostingView
    }

    private func setupNodeDragCallback(canvas: CanvasViewportView) {
        // 拖动中帧级回调：实时更新物理引擎端点
        canvas.onNodeFramesDuringDrag = { [weak self] draggedIds in
            guard let self, let ws = self.currentWorkspace else { return }
            // 只更新涉及被拖动节点的连接绳索端点
            self.updatePhysicsAnchorsForNodes(draggedIds, workspace: ws)
        }

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
        // 右键菜单回调
        canvas.onContextMenuClose = { [weak self] id in
            self?.removeNode(id: id, from: self?.currentWorkspace)
        }
        canvas.onContextMenuRename = { [weak self] id in
            // 通过通知让 UI 层弹出重命名输入框
            NotificationCenter.default.post(
                name: .editTerminalRequested,
                object: nil,
                userInfo: ["nodeId": id]
            )
        }
        canvas.onContextMenuLockToggle = { [weak self] id in
            guard let ws = self?.currentWorkspace,
                  let idx = ws.nodes.firstIndex(where: { $0.id == id }) else { return }
            let newLocked = !ws.nodes[idx].isLocked
            self?.handleLockToggle(id: id, locked: newLocked)
        }
        // 右键菜单：编辑终端（发送通知，附带 TerminalContent 数据）
        canvas.onContextMenuEditTerminal = { [weak self] id in
            guard let ws = self?.currentWorkspace,
                  let node = ws.nodes.first(where: { $0.id == id }),
                  case .terminal(let tc) = node.content else { return }
            NotificationCenter.default.post(
                name: .editTerminalRequested,
                object: nil,
                userInfo: ["nodeId": id, "terminalContent": tc]
            )
        }
        // 右键菜单：开始连接（直接在 NSView 层设置起点，避免 SwiftUI 往返延迟）
        canvas.onContextMenuConnect = { [weak canvas] id in
            canvas?.selectedNodeIds = [id]
            canvas?.connectingFromNodeId = id
            NotificationCenter.default.post(
                name: .contextMenuConnect,
                object: nil,
                userInfo: ["nodeId": id]
            )
        }
        // 右键菜单：分配角色（Terminal 专属）
        canvas.onContextMenuAssignRole = { id in
            NotificationCenter.default.post(
                name: .contextMenuAssignRole,
                object: nil,
                userInfo: ["nodeId": id]
            )
        }
        // 右键菜单：切换 Maestro 模式（Terminal 专属）
        canvas.onContextMenuToggleMaestro = { id in
            NotificationCenter.default.post(
                name: .contextMenuToggleMaestro,
                object: nil,
                userInfo: ["nodeId": id]
            )
        }
        // 右键菜单：清除缓冲区（Terminal 专属）
        canvas.onContextMenuClearBuffer = { [weak self] id in
            self?.handleClearBuffer(terminalId: id)
        }
        // 右键菜单：重新加载终端（Terminal 专属）
        canvas.onContextMenuReloadTerminal = { [weak self] id in
            self?.handleReloadTerminal(terminalId: id)
        }
        // 右键菜单：拷贝终端内容（Terminal 专属）
        canvas.onContextMenuCopyTerminal = { [weak self] id in
            self?.handleCopyTerminal(terminalId: id)
        }
        // 右键菜单：切换监控活动（Terminal 专属）
        canvas.onContextMenuToggleMonitor = { [weak self] id in
            self?.handleToggleMonitor(terminalId: id)
        }
        // 节点层级变更：同步到 workspace 持久化（canvas.currentNodes 已由 bringNodesToFront 更新）
        canvas.onNodeZIndexChanged = { [weak self] nodeId, newZIndex in
            guard let ws = self?.currentWorkspace,
                  let idx = ws.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
            ws.nodes[idx].zIndex = newZIndex
        }
    }

    func saveWorkspace() {
        guard let ws = currentWorkspace else { return }
        Task {
            do {
                try await ws.save()
            } catch {
                logger.error("Failed to save workspace: \(error.localizedDescription)")
            }
        }
    }

    private func setupDrawingOverlay(canvas: CanvasViewportView) {
        let overlay = DrawingOverlayView(frame: canvas.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.canvasOrigin = canvas.canvasOrigin
        overlay.zoom = canvas.zoom
        canvas.addSubview(overlay)
        canvas.drawingOverlayView = overlay
    }

    private func setupOverlay(canvas: CanvasViewportView) {
        let overlay = ConnectionOverlayView(frame: canvas.bounds)
        overlay.autoresizingMask = [.width, .height]
        // 连接线层插在节点层之下，节点重叠时节点始终显示在连接线上方
        if let nodesView = canvas.nodesHostingView {
            canvas.addSubview(overlay, positioned: .below, relativeTo: nodesView)
        } else {
            canvas.addSubview(overlay)
        }
        overlayView = overlay
        // 注册 overlay 引用到画布（供临时连线同步使用）
        canvas.connectionOverlayView = overlay

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

        // 先更新 currentNodes（触发排序缓存更新），再用排序后的数组构建 SwiftUI 视图
        // 重建 nodeCanvasFrames：清理已删除节点的旧条目，避免旧 UUID 残留干扰 hitTest 和拖拽
        let activeIds = Set(nodes.map { $0.id })
        canvas.nodeCanvasFrames = canvas.nodeCanvasFrames.filter { activeIds.contains($0.key) }
        for node in nodes {
            canvas.nodeCanvasFrames[node.id] = node.frame
        }
        canvas.currentNodes = nodes

        // 视口裁剪：仅将可见节点传入 SwiftUI 渲染层
        let visibleNodes = canvas.viewportCulledNodes()

        nodesHostingView?.rootView = CanvasNodesSwiftUIView(
            nodes: visibleNodes,
            canvasOrigin: canvas.canvasOrigin,
            zoom: canvas.zoom,
            selectedNodeIds: canvas.selectedNodeIds,
            lockedNodeIds: lockedIds,
            workspace: workspace,
            onActivated: { [weak canvas] id in
                guard let canvas else { return }
                if let provider = TerminalManager.shared.providers[id],
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

        // 确保连接线层始终在节点层之下（节点重叠时节点遮挡连接线）
        if let overlay = overlayView, let nodesView = nodesHostingView {
            canvas.addSubview(overlay, positioned: .below, relativeTo: nodesView)
        } else if let overlay = overlayView {
            canvas.addSubview(overlay)
        }

        // drawingOverlayView 在节点层上方（用于 drawing 选中边框）
        if let drawingOverlay = canvas.drawingOverlayView {
            canvas.addSubview(drawingOverlay)
        }

        // 保证 snapGuideView 始终在最顶层
        if let snapView = canvas.snapGuideView {
            canvas.addSubview(snapView)
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
        let newContent: NodeContent?
        switch ws.nodes[idx].content {
        case .terminal(var tc):
            tc.name = newName
            newContent = .terminal(tc)
        case .stickyNote(var nc):
            nc.hasCustomName = true
            nc.fileName = newName.hasSuffix(".md") ? newName : "\(newName).md"
            newContent = .stickyNote(nc)
        case .portal(var pc):
            pc.name = newName
            newContent = .portal(pc)
        case .fileTree(var fc):
            fc.name = newName
            newContent = .fileTree(fc)
        default:
            newContent = nil
        }
        if let content = newContent {
            ws.nodes[idx].content = content
            // canvasNodeContentChanged observer 统一处理：updateNodeContentInPlace + displayName + rootView 刷新
            NotificationCenter.default.post(
                name: .canvasNodeContentChanged,
                object: nil,
                userInfo: ["nodeId": id, "content": content]
            )
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
        canvas?.updateNodeLockedInPlace(id: id, isLocked: locked)
        saveWorkspace()
    }

}
