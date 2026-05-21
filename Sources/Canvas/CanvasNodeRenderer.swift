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

    /// 复用的悬链线计算器（避免每条连线每帧都 alloc 新实例）
    private let ropeSimulation = RopeSimulation()

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
        // 节点层级变更：同步到 workspace 持久化（canvas.currentNodes 已由 bringNodesToFront 更新）
        canvas.onNodeZIndexChanged = { [weak self] nodeId, newZIndex in
            guard let ws = self?.currentWorkspace,
                  let idx = ws.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
            ws.nodes[idx].zIndex = newZIndex
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
        canvas.addSubview(overlay)
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

        if let overlay = overlayView {
            canvas.addSubview(overlay)
        }

        // drawingOverlayView 在连接线层上方
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
            canvas?.updateNodeContentInPlace(id: id, content: content)
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

    // MARK: - 通知观察者

    private func setupActivationObserver() {
        let obs = NotificationCenter.default.addObserver(
            forName: .canvasNodeActivated, object: nil, queue: .main
        ) { [weak self] notif in
            guard let id = notif.userInfo?["nodeId"] as? UUID else { return }
            if let provider = TerminalManager.shared.providers[id],
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
                  let ids = notif.userInfo?["selectedIds"] as? Set<UUID> else { return }
            guard let current = self.nodesHostingView?.rootView else { return }
            // 注意：不能仅凭 selectedNodeIds 不变就跳过——zIndex 变化时节点排序已更新，
            // 必须用最新的 viewportCulledNodes() 重建 rootView 才能让渲染层反映新层级顺序
            let lockedIds = Set(canvas.currentNodes.filter { $0.isLocked }.map { $0.id })
            self.nodesHostingView?.rootView = CanvasNodesSwiftUIView(
                nodes: canvas.viewportCulledNodes(),
                canvasOrigin: canvas.canvasOrigin,
                zoom: canvas.zoom,
                selectedNodeIds: ids,
                lockedNodeIds: lockedIds,
                workspace: current.workspace,
                dropTargetNodeId: current.dropTargetNodeId,
                onActivated: current.onActivated,
                onClose: current.onClose,
                onRename: current.onRename,
                onDuplicate: current.onDuplicate,
                onLockToggle: current.onLockToggle
            )
        }
        notificationObservers.append(obs)
    }

    private func setupDropTargetObserver() {
        let obs = NotificationCenter.default.addObserver(
            forName: .canvasDropTargetChanged, object: nil, queue: .main
        ) { [weak self] notif in
            guard let self,
                  let canvas = self.canvas else { return }
            let dropTargetId = notif.userInfo?["dropTargetNodeId"] as? UUID
            guard let current = self.nodesHostingView?.rootView,
                  current.dropTargetNodeId != dropTargetId else { return }
            self.nodesHostingView?.rootView = CanvasNodesSwiftUIView(
                nodes: canvas.viewportCulledNodes(),
                canvasOrigin: canvas.canvasOrigin,
                zoom: canvas.zoom,
                selectedNodeIds: current.selectedNodeIds,
                lockedNodeIds: current.lockedNodeIds,
                workspace: current.workspace,
                dropTargetNodeId: dropTargetId,
                onActivated: current.onActivated,
                onClose: current.onClose,
                onRename: current.onRename,
                onDuplicate: current.onDuplicate,
                onLockToggle: current.onLockToggle
            )
        }
        notificationObservers.append(obs)
    }

    private func setupNodeStateObservers() {
        // 节点 isLocked 变更：同步到 canvas.currentNodes（WorkspaceCanvasView 直接改 ws.nodes 不经过 renderer）
        let lockObs = NotificationCenter.default.addObserver(
            forName: .canvasNodeLockChanged, object: nil, queue: .main
        ) { [weak self] notif in
            guard let id = notif.userInfo?["nodeId"] as? UUID,
                  let locked = notif.userInfo?["isLocked"] as? Bool else { return }
            self?.canvas?.updateNodeLockedInPlace(id: id, isLocked: locked)
        }
        notificationObservers.append(lockObs)

        // 节点 content 变更：同步到 canvas.currentNodes
        let contentObs = NotificationCenter.default.addObserver(
            forName: .canvasNodeContentChanged, object: nil, queue: .main
        ) { [weak self] notif in
            guard let id = notif.userInfo?["nodeId"] as? UUID,
                  let content = notif.userInfo?["content"] as? NodeContent else { return }
            self?.canvas?.updateNodeContentInPlace(id: id, content: content)
        }
        notificationObservers.append(contentObs)
    }

    // MARK: - 连线物理同步

    /// 连接元数据（用于渲染时查找 status）
    private struct ConnectionMeta {
        let id: UUID
        let nodeIdA: UUID
        let nodeIdB: UUID
    }

    /// 当前活跃的连接元数据列表（在 syncConnections 中构建）
    private var activeConnections: [ConnectionMeta] = []

    /// 连接状态缓存（避免每条连线每帧 O(n) 查找）
    /// 在 syncConnections 中构建，在物理回调中使用
    private var connectionStatusCache: [UUID: ConnectionStatus] = [:]

    /// 初始化物理模拟回调（在 setupOverlay 后调用一次）
    private func setupPhysicsCallbacks() {
        ropeSimulation.onTick = { [weak self] allPoints in
            self?.renderConnectionsFromPhysics(allPoints)
        }
        ropeSimulation.onSleep = { [weak self] allPoints in
            self?.renderConnectionsFromPhysics(allPoints)
        }
    }

    /// 共享的物理回调渲染方法：将画布坐标控制点转为屏幕坐标并推送给 overlay
    private func renderConnectionsFromPhysics(_ allPoints: [UUID: [CGPoint]]) {
        guard let overlay = overlayView, let canvas else { return }
        var renderables: [RenderableConnection] = []
        for meta in activeConnections {
            guard let canvasPoints = allPoints[meta.id] else { continue }
            let screenPoints = canvasPoints.map { canvas.canvasToScreen($0) }
            let status = connectionStatusCache[meta.id] ?? .idle
            renderables.append(RenderableConnection(id: meta.id, screenPoints: screenPoints, status: status))
        }
        overlay.connections = renderables
    }

    /// 轻量级重渲染：仅将已有的物理控制点重新转换为屏幕坐标
    /// 用于 viewport pan/zoom 变化时（节点画布坐标不变，只有屏幕映射变了）
    func rerenderConnections() {
        renderConnectionsFromPhysics(ropeSimulation.allPoints())
    }

    /// 同步连接列表 + 更新物理端点
    /// 调用时机：节点/连接数量变化、zoom/pan 变化、节点拖动中
    func syncConnections(workspace: WorkspaceManager) {
        guard let overlay = overlayView, let canvas else { return }

        var metas: [ConnectionMeta] = []
        var activeIds: Set<UUID> = []
        var anchorUpdates: [(id: UUID, anchorA: CGPoint, anchorB: CGPoint)] = []

        // 收集所有连接的端点（计算边缘锚点，而非中心点）
        for conn in workspace.connections {
            guard let frameA = liveNodeFrame(id: conn.terminalIdA, in: workspace),
                  let frameB = liveNodeFrame(id: conn.terminalIdB, in: workspace) else { continue }
            let centerB = CGPoint(x: frameB.midX, y: frameB.midY)
            let centerA = CGPoint(x: frameA.midX, y: frameA.midY)
            let anchorA = edgeAnchor(of: frameA, toward: centerB)
            let anchorB = edgeAnchor(of: frameB, toward: centerA)
            activeIds.insert(conn.id)
            metas.append(ConnectionMeta(id: conn.id, nodeIdA: conn.terminalIdA, nodeIdB: conn.terminalIdB))
            anchorUpdates.append((id: conn.id, anchorA: anchorA, anchorB: anchorB))
        }

        for conn in workspace.noteConnections {
            guard let frameA = liveNodeFrame(id: conn.terminalId, in: workspace),
                  let frameB = liveNodeFrame(id: conn.noteNodeId, in: workspace) else { continue }
            let centerB = CGPoint(x: frameB.midX, y: frameB.midY)
            let centerA = CGPoint(x: frameA.midX, y: frameA.midY)
            let anchorA = edgeAnchor(of: frameA, toward: centerB)
            let anchorB = edgeAnchor(of: frameB, toward: centerA)
            activeIds.insert(conn.id)
            metas.append(ConnectionMeta(id: conn.id, nodeIdA: conn.terminalId, nodeIdB: conn.noteNodeId))
            anchorUpdates.append((id: conn.id, anchorA: anchorA, anchorB: anchorB))
        }

        for conn in workspace.portalConnections {
            guard let frameA = liveNodeFrame(id: conn.terminalId, in: workspace),
                  let frameB = liveNodeFrame(id: conn.portalNodeId, in: workspace) else { continue }
            let centerB = CGPoint(x: frameB.midX, y: frameB.midY)
            let centerA = CGPoint(x: frameA.midX, y: frameA.midY)
            let anchorA = edgeAnchor(of: frameA, toward: centerB)
            let anchorB = edgeAnchor(of: frameB, toward: centerA)
            activeIds.insert(conn.id)
            metas.append(ConnectionMeta(id: conn.id, nodeIdA: conn.terminalId, nodeIdB: conn.portalNodeId))
            anchorUpdates.append((id: conn.id, anchorA: anchorA, anchorB: anchorB))
        }

        for conn in workspace.noteToNoteConnections {
            guard let frameA = liveNodeFrame(id: conn.noteNodeIdA, in: workspace),
                  let frameB = liveNodeFrame(id: conn.noteNodeIdB, in: workspace) else { continue }
            let centerB = CGPoint(x: frameB.midX, y: frameB.midY)
            let centerA = CGPoint(x: frameA.midX, y: frameA.midY)
            let anchorA = edgeAnchor(of: frameA, toward: centerB)
            let anchorB = edgeAnchor(of: frameB, toward: centerA)
            activeIds.insert(conn.id)
            metas.append(ConnectionMeta(id: conn.id, nodeIdA: conn.noteNodeIdA, nodeIdB: conn.noteNodeIdB))
            anchorUpdates.append((id: conn.id, anchorA: anchorA, anchorB: anchorB))
        }

        for conn in workspace.portalToPortalConnections {
            guard let frameA = liveNodeFrame(id: conn.portalIdA, in: workspace),
                  let frameB = liveNodeFrame(id: conn.portalIdB, in: workspace) else { continue }
            let centerB = CGPoint(x: frameB.midX, y: frameB.midY)
            let centerA = CGPoint(x: frameA.midX, y: frameA.midY)
            let anchorA = edgeAnchor(of: frameA, toward: centerB)
            let anchorB = edgeAnchor(of: frameB, toward: centerA)
            activeIds.insert(conn.id)
            metas.append(ConnectionMeta(id: conn.id, nodeIdA: conn.portalIdA, nodeIdB: conn.portalIdB))
            anchorUpdates.append((id: conn.id, anchorA: anchorA, anchorB: anchorB))
        }

        // 更新活跃连接元数据
        activeConnections = metas

        // 清理已删除的绳索
        let existingIds = Set(ropeSimulation.ropes.keys)
        for deadId in existingIds.subtracting(activeIds) {
            ropeSimulation.removeRope(id: deadId)
        }

        // 添加新绳索 / 更新已有绳索的端点
        for update in anchorUpdates {
            if ropeSimulation.ropes[update.id] != nil {
                ropeSimulation.updateAnchors(id: update.id, anchorA: update.anchorA, anchorB: update.anchorB)
            } else {
                ropeSimulation.addRope(id: update.id, anchorA: update.anchorA, anchorB: update.anchorB)
            }
        }

        // 构建连接状态缓存（O(n) 一次，后续物理回调 O(1) 查询）
        rebuildConnectionStatusCache()

        // 立即渲染当前帧（确保连线可见，不论物理是否在运行）
        var renderables: [RenderableConnection] = []
        for meta in metas {
            guard let canvasPoints = ropeSimulation.points(for: meta.id) else { continue }
            let screenPoints = canvasPoints.map { canvas.canvasToScreen($0) }
            let status = connectionStatusCache[meta.id] ?? .idle
            renderables.append(RenderableConnection(id: meta.id, screenPoints: screenPoints, status: status))
        }
        overlay.connections = renderables
    }

    /// 获取节点的实时 frame（优先使用 canvas 中的拖拽实时值，否则从 workspace 取）
    private func liveNodeFrame(id: UUID, in workspace: WorkspaceManager) -> CGRect? {
        // 拖动期间 canvas.nodeCanvasFrames 持有最新 frame
        if let liveFrame = canvas?.nodeCanvasFrames[id] {
            return liveFrame
        }
        return workspace.nodes.first { $0.id == id }?.frame
    }

    // MARK: - 边缘锚点计算

    /// 计算连接线锚点：从节点 frame 的中心出发，向目标中心方向与边框的交点
    /// 这样连线从节点边缘出发而非中心，与 Maestri 行为一致
    private func edgeAnchor(of frame: CGRect, toward target: CGPoint) -> CGPoint {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let dx = target.x - center.x
        let dy = target.y - center.y

        // 两节点重叠或完全重合时退化为中心
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return center }

        let halfW = frame.width / 2.0
        let halfH = frame.height / 2.0

        // 通过比例判断射线先碰到左右边还是上下边
        // t 表示从 center 到 target 方向上，到达边框的参数值
        var t: CGFloat = .greatestFiniteMagnitude

        if abs(dx) > 0.001 {
            let tx = halfW / abs(dx)
            if tx < t { t = tx }
        }
        if abs(dy) > 0.001 {
            let ty = halfH / abs(dy)
            if ty < t { t = ty }
        }

        return CGPoint(x: center.x + dx * t, y: center.y + dy * t)
    }

    /// 重建连接状态缓存（从 ConnectionManager 的活跃连接中构建 [connectionId: status] 字典）
    private func rebuildConnectionStatusCache() {
        var cache: [UUID: ConnectionStatus] = [:]
        for meta in activeConnections {
            // 通过 connectionId 直接查找（O(1) 字典查找）
            if let active = ConnectionManager.shared.connections[meta.id] {
                cache[meta.id] = active.status
            } else {
                // 降级：按节点对匹配（兼容 connectionId 不一致的情况）
                let matched = ConnectionManager.shared.connections.values
                    .first { $0.nodeIdA == meta.nodeIdA && $0.nodeIdB == meta.nodeIdB }
                cache[meta.id] = matched?.status ?? .idle
            }
        }
        connectionStatusCache = cache
    }

    /// 拖动中增量更新：只更新涉及被拖动节点的绳索端点（高效路径，不重建整个连接列表）
    private func updatePhysicsAnchorsForNodes(_ movedNodeIds: Set<UUID>, workspace: WorkspaceManager) {
        var updates: [(id: UUID, anchorA: CGPoint, anchorB: CGPoint)] = []

        for meta in activeConnections {
            // 只处理涉及被拖动节点的连接
            guard movedNodeIds.contains(meta.nodeIdA) || movedNodeIds.contains(meta.nodeIdB) else { continue }
            guard let frameA = liveNodeFrame(id: meta.nodeIdA, in: workspace),
                  let frameB = liveNodeFrame(id: meta.nodeIdB, in: workspace) else { continue }
            let centerA = CGPoint(x: frameA.midX, y: frameA.midY)
            let centerB = CGPoint(x: frameB.midX, y: frameB.midY)
            let anchorA = edgeAnchor(of: frameA, toward: centerB)
            let anchorB = edgeAnchor(of: frameB, toward: centerA)
            updates.append((id: meta.id, anchorA: anchorA, anchorB: anchorB))
        }

        if !updates.isEmpty {
            ropeSimulation.updateAnchors(updates: updates)
            // 立即渲染一帧（确保拖动时连线位置实时更新，不需要等待物理 tick 触发）
            renderConnectionsFromPhysics(ropeSimulation.allPoints())
        }
    }
}
