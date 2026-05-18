import AppKit
import SwiftUI
import WebKit
import OSLog

/// 画布节点渲染引擎
/// 维护 CanvasNode → NSView 的双向映射，负责节点视图的创建/更新/销毁
@MainActor
final class CanvasNodeRenderer {
    private let logger = Logger.make(category: "CanvasNodeRenderer")
    private weak var canvas: CanvasViewportView?
    private var renderedNodeIds: Set<UUID> = []
    /// 当前工作区（供节点回调使用）
    private weak var currentWorkspace: WorkspaceManager?
    private var notificationObservers: [NSObjectProtocol] = []
    /// 当前可用角色列表（由外部在 sync 前注入）
    var rolePresets: [RolePreset] = []

    // 保存节点视图引用，避免 ARC 提前释放
    private var terminalViews: [UUID: TerminalNodeView] = [:]
    private var noteViewControllers: [UUID: NoteNodeViewController] = [:]
    private var portalViews: [UUID: PortalNodeView] = [:]
    private var fileTreeViews: [UUID: FileTreeNodeView] = [:]
    private var textViews: [UUID: TextNodeView] = [:]
    private var drawingViews: [UUID: DrawingNodeView] = [:]

    // 连线层
    private(set) var overlayView: ConnectionOverlayView?

    init(canvas: CanvasViewportView) {
        self.canvas = canvas
        setupOverlay(canvas: canvas)
        observePortalReplacement()
        setupNodeDragCallback(canvas: canvas)
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

    private func observePortalReplacement() {
        let observer = NotificationCenter.default.addObserver(
            forName: .portalWebViewReplaced,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            self?.handlePortalWebViewReplaced(notif)
        }
        notificationObservers.append(observer)
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func handlePortalWebViewReplaced(_ notif: Notification) {
        guard let info = notif.userInfo else { return }
        let pairs: [(UUID, WKWebView)] = [
            (info["portalIdA"] as? UUID, info["webViewA"] as? WKWebView),
            (info["portalIdB"] as? UUID, info["webViewB"] as? WKWebView),
        ].compactMap { (id, wv) in
            guard let id, let wv else { return nil }
            return (id, wv)
        }
        for (portalId, newWebView) in pairs {
            if let nodeView = portalViews[portalId] {
                nodeView.contentView.subviews.forEach { $0.removeFromSuperview() }
                nodeView.contentView.addSubviewFillingBounds(newWebView)
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

    // MARK: - 同步节点列表

    /// 根据 workspace.nodes 增量更新画布上的节点视图
    func sync(nodes: [CanvasNode], workspace: WorkspaceManager) {
        guard let canvas else { return }
        currentWorkspace = workspace  // 更新引用供节点回调使用

        let currentIds = Set(nodes.map { $0.id })
        let toAdd = currentIds.subtracting(renderedNodeIds)
        let toRemove = renderedNodeIds.subtracting(currentIds)

        // 移除已删除的节点
        for id in toRemove {
            canvas.removeNodeView(id: id)
            terminalViews.removeValue(forKey: id)
            noteViewControllers.removeValue(forKey: id)
            portalViews.removeValue(forKey: id)
            fileTreeViews.removeValue(forKey: id)
            textViews.removeValue(forKey: id)
            drawingViews.removeValue(forKey: id)
            renderedNodeIds.remove(id)
        }

        // 按 zIndex 升序添加新节点（zIndex 小的先添加，视觉上在下层）
        let sortedNew = nodes.filter { toAdd.contains($0.id) }.sorted { $0.zIndex < $1.zIndex }
        for node in sortedNew {
            addNodeView(node: node, workspace: workspace)
        }

        // 更新所有节点 frame（处理节点移动）
        for node in nodes {
            canvas.updateNodeFrame(id: node.id, canvasFrame: node.frame)
        }

        // 按 zIndex 重新排序已渲染的节点视图（确保层级正确）
        let sortedAll = nodes.sorted { $0.zIndex < $1.zIndex }
        for node in sortedAll {
            if let view = canvas.nodeViews[node.id] {
                canvas.addSubview(view)  // re-add 到顶层（保持 zIndex 顺序）
            }
        }

        // 提升连线层到最顶层
        if let overlay = overlayView {
            canvas.addSubview(overlay)
        }
    }

    // MARK: - 创建节点视图

    private func addNodeView(node: CanvasNode, workspace: WorkspaceManager) {
        guard let canvas else { return }

        let view: NSView
        switch node.content {
        case .terminal(let tc):
            view = makeTerminalView(node: node, tc: tc, workspaceId: workspace.id)
        case .stickyNote(let nc):
            view = makeNoteView(node: node, nc: nc, workspace: workspace)
        case .portal(let pc):
            view = makePortalView(node: node, pc: pc)
        case .fileTree(let fc):
            view = makeFileTreeView(node: node, fc: fc)
        case .text(let tc):
            view = makeTextView(node: node, tc: tc)
        case .drawing(let dc):
            view = makeDrawingView(node: node, dc: dc)
        }

        // Resize 回写：BaseNodeView.onFrameChanged → workspace.updateNodeFrame
        // 移动拖动由 canvas 层（onNodeDragEnded）统一处理，不走此回调
        if let baseView = view as? BaseNodeView {
            let nodeId = node.id
            let weakWorkspace = workspace
            let weakCanvas = canvas

            baseView.onFrameChanged = { [weak weakCanvas] screenFrame in
                guard let cv = weakCanvas else { return }
                // screenFrame 是缩放后的屏幕尺寸，需转回画布坐标
                let canvasOrigin = cv.screenToCanvas(screenFrame.origin)
                let canvasFrame = CGRect(
                    x: canvasOrigin.x,
                    y: canvasOrigin.y,
                    width: screenFrame.width / cv.zoom,
                    height: screenFrame.height / cv.zoom
                )
                Task { @MainActor in
                    weakWorkspace.updateNodeFrame(id: nodeId, frame: canvasFrame)
                    cv.nodeCanvasFrames[nodeId] = canvasFrame
                }
            }
        }

        canvas.addNodeView(view, id: node.id, canvasFrame: node.frame)
        renderedNodeIds.insert(node.id)
        let nodeIdStr = node.id.uuidString.prefix(8)
        let contentLabel = typeLabel(node.content)
        logger.debug("Rendered node \(nodeIdStr) (\(contentLabel))")
    }

    // MARK: - Terminal 节点

    private func makeTerminalView(node: CanvasNode, tc: TerminalContent, workspaceId: UUID? = nil) -> TerminalNodeView {
        let nodeView = TerminalNodeView()
        nodeView.nodeId = node.id
        nodeView.title = tc.name
        nodeView.isLocked = node.isLocked
        nodeView.showMaestroIndicator = tc.isManager
        // 根据 TerminalContent.icon/color 设置 agent 样式
        nodeView.setAgentStyle(icon: tc.icon, colorHex: tc.color)

        // 使用 tc.id 作为 terminal id（TerminalManager 的 key），tc.id 在 JSON 中持久化
        let terminalId = tc.id

        // 直接用 SwiftTermProvider 创建 LocalProcessTerminalView，跳过 NSHostingView
        // NSHostingView 会拦截键盘事件给 SwiftUI 焦点系统，导致终端无法接收键盘输入
        let provider = SwiftTermProvider(
            terminalId: terminalId,
            command: tc.command,
            workingDirectory: tc.workingDirectory
        )
        provider.serverPort = InterAgentServer.shared.port
        provider.workspaceId = workspaceId
        let termView = provider.start(in: .zero)
        nodeView.contentView.addSubviewFillingBounds(termView)

        // 绑定 output 回调（与原 TerminalEmbeddedView.makeNSView 逻辑一致）
        if let session = TerminalManager.shared.terminals[terminalId] {
            provider.onOutput = { text in
                Task { @MainActor in session.recordOutput(text) }
                provider.recordOutputForScrollback(text)
            }
        }
        TerminalProviderRegistry.shared.register(terminalId: terminalId, provider: provider)

        // PTY resize：contentView 尺寸变化时更新行列数
        termView.autoresizingMask = [.width, .height]

        // 确保 TerminalManager 有对应会话
        if TerminalManager.shared.terminals[tc.id] == nil {
            let preset = AgentPreset.defaults.first { $0.agentType == tc.agentType }
                ?? AgentPreset.defaults.last!
            _ = TerminalManager.shared.createTerminal(
                id: tc.id,
                workingDirectory: tc.workingDirectory,
                preset: preset
            )
        }

        // 空闲状态同步
        if let session = TerminalManager.shared.terminals[tc.id] {
            nodeView.isIdle = session.isIdle
        }

        // 回调：传入 currentWorkspace 确保节点从 workspace.nodes 中移除
        nodeView.onClose = { [weak self] in
            self?.removeNode(id: node.id, from: self?.currentWorkspace)
        }
        nodeView.onEdit = {
            NotificationCenter.default.post(
                name: .editTerminalRequested,
                object: nil,
                userInfo: ["nodeId": node.id, "terminalContent": tc]
            )
        }

        // 键盘焦点透传：直接让 LocalProcessTerminalView 成为 firstResponder
        let focusTermId = tc.id
        nodeView.onFocusRequested = {
            guard let tv = TerminalProviderRegistry.shared.provider(for: focusTermId)?.terminalView else {
                return
            }
            tv.window?.makeFirstResponder(tv)
        }

        // 滚动锁定回调：右键菜单切换时同步到 SwiftTermProvider
        let termId = tc.id
        nodeView.onScrollLockToggle = { locked in
            TerminalProviderRegistry.shared.provider(for: termId)?.setAutoScrollLocked(locked)
        }

        // 角色分配回调：立即重启终端，注入新角色
        nodeView.availableRoles = rolePresets
        let nodeId = node.id
        let agentType = tc.agentType
        let tcWorkingDir = tc.workingDirectory
        let tcCommand = tc.command
        nodeView.onAssignRole = { [weak self] role in
            guard let self else { return }
            let wsId = self.currentWorkspace?.id
            let preset = AgentPreset.defaults.first { $0.agentType == agentType }
                ?? AgentPreset.defaults.last!
            // 计算新的起始目录
            let newWorkingDir: String
            if let role {
                newWorkingDir = RoleInjector.shared.prepareRoleDirectory(
                    roleId: role.id,
                    rolePrompt: role.prompt,
                    workingDirectory: tcWorkingDir
                )
            } else {
                newWorkingDir = tcWorkingDir
            }
            // 重启终端（删除旧 session，创建新 session）
            TerminalManager.shared.removeTerminal(id: termId)
            Task { @MainActor in
                _ = TerminalManager.shared.createTerminal(
                    id: termId,
                    workingDirectory: newWorkingDir,
                    preset: preset,
                    role: role,
                    workspaceId: wsId
                )
                // 通知 SwiftTermProvider 以新目录重启进程
                TerminalProviderRegistry.shared.provider(for: termId)?.restartProcess(
                    command: tcCommand.isEmpty ? "zsh" : tcCommand,
                    workingDirectory: newWorkingDir
                )
            }
            self.logger.info("Assigned role '\(role?.name ?? "none")' to terminal \(nodeId)")
        }

        terminalViews[node.id] = nodeView
        setupLockCallback(nodeView: nodeView, node: node)
        return nodeView
    }

    // MARK: - Note 节点

    private func makeNoteView(node: CanvasNode, nc: StickyNoteContent, workspace: WorkspaceManager) -> NoteNodeView {
        let nodeView = NoteNodeView()
        nodeView.nodeId = node.id
        nodeView.title = nc.fileName ?? "Note"
        nodeView.setColor(hex: nc.color)
        nodeView.isLocked = node.isLocked

        // 解析 Note 文件路径：支持 managed 和 custom 两种存储模式
        let filePath: String
        switch nc.storageMode {
        case .custom(let customPath):
            // 自定义路径：直接使用，文件可能不在应用数据目录内
            filePath = customPath
        case .managed:
            let notesDir = PersistenceManager.shared.notesDirURL(workspaceId: workspace.id)
            if let fn = nc.fileName {
                filePath = notesDir.appendingPathComponent(fn).path
            } else {
                filePath = notesDir.appendingPathComponent("note-\(node.id.uuidString.prefix(8)).md").path
            }
        }

        // 确保文件存在（managed 模式自动创建，custom 模式仅在文件不存在时提示）
        if !FileManager.default.fileExists(atPath: filePath) {
            if case .managed = nc.storageMode {
                do {
                    try "".write(toFile: filePath, atomically: true, encoding: .utf8)
                } catch {
                    logger.error("Failed to create note file at \(filePath): \(error.localizedDescription)")
                }
            } else {
                logger.warning("Custom note file not found at \(filePath)")
            }
        }

        // 注册到 NoteRegistry
        NoteRegistry.shared.register(name: nc.fileName ?? node.id.uuidString, filePath: filePath, nodeId: node.id)

        // 嵌入 NoteNodeViewController
        let vc = NoteNodeViewController(noteId: node.id, filePath: filePath)
        // 首行变化时自动更新节点标题
        // 仅在 hasCustomName=false（未手动重命名）时跟随内容首行
        vc.onTitleChanged = { [weak nodeView, weak self] title in
            guard let self, let ws = self.currentWorkspace,
                  let nodeIdx = ws.nodes.firstIndex(where: { $0.id == node.id }),
                  case .stickyNote(let currentNc) = ws.nodes[nodeIdx].content,
                  !currentNc.hasCustomName
            else { return }
            nodeView?.title = title
        }
        // 重命名时设置 hasCustomName=true 并持久化
        nodeView.onRename = { [weak self] newName in
            guard let self, let workspace = self.currentWorkspace else { return }
            if let idx = workspace.nodes.firstIndex(where: { $0.id == node.id }),
               case .stickyNote(var nc) = workspace.nodes[idx].content {
                nc.hasCustomName = true
                nc.fileName = newName.hasSuffix(".md") ? newName : "\(newName).md"
                workspace.nodes[idx].content = .stickyNote(nc)
                self.saveWorkspace()
            }
        }
        // "移动到…" 回调：物理移动 .md 文件到目标目录，更新 storageMode 为 .custom(path)
        nodeView.onMoveTo = { [weak self] targetDir in
            guard let self, let workspace = self.currentWorkspace,
                  let idx = workspace.nodes.firstIndex(where: { $0.id == node.id }),
                  case .stickyNote(var nc) = workspace.nodes[idx].content else { return }
            let fileName = nc.fileName ?? "\(node.id.uuidString.prefix(8)).md"
            let destURL = targetDir.appendingPathComponent(fileName)
            let srcURL = URL(fileURLWithPath: filePath)
            do {
                if srcURL.path != destURL.path {
                    // 如果目标文件已存在，先删除（保持与 Maestri 行为一致）
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.moveItem(at: srcURL, to: destURL)
                }
                nc.storageMode = .custom(path: destURL.path)
                workspace.nodes[idx].content = .stickyNote(nc)
                // 更新 NoteRegistry
                NoteRegistry.shared.register(name: fileName, filePath: destURL.path, nodeId: node.id)
                self.saveWorkspace()
                self.logger.info("Note moved to \(destURL.path)")
            } catch {
                self.logger.error("Failed to move note: \(error.localizedDescription)")
            }
        }

        noteViewControllers[node.id] = vc
        setupLockCallback(nodeView: nodeView, node: node)
        nodeView.onClose = { [weak self] in self?.removeNode(id: node.id, from: self?.currentWorkspace) }
        vc.loadViewIfNeeded()
        nodeView.contentView.addSubviewFillingBounds(vc.view)

        return nodeView
    }

    // MARK: - Portal 节点

    private func makePortalView(node: CanvasNode, pc: PortalContent) -> PortalNodeView {
        let nodeView = PortalNodeView()
        nodeView.nodeId = node.id
        nodeView.title = pc.name
        nodeView.isLocked = node.isLocked

        let webView = PortalWebViewStore.shared.createWebView(
            for: pc.id,
            initialURL: pc.currentURL.isEmpty ? nil : pc.currentURL
        )
        nodeView.contentView.addSubviewFillingBounds(webView)

        portalViews[node.id] = nodeView
        setupLockCallback(nodeView: nodeView, node: node)
        nodeView.onClose = { [weak self] in self?.removeNode(id: node.id, from: self?.currentWorkspace) }
        return nodeView
    }

    // MARK: - FileTree 节点

    private func makeFileTreeView(node: CanvasNode, fc: FileTreeContent) -> FileTreeNodeView {
        let nodeView = FileTreeNodeView()
        nodeView.nodeId = node.id
        nodeView.title = fc.name
        nodeView.isLocked = node.isLocked

        let outlineView = FileTreeOutlineView(rootPath: fc.rootPath)
        nodeView.contentView.addSubviewFillingBounds(outlineView)

        fileTreeViews[node.id] = nodeView
        setupLockCallback(nodeView: nodeView, node: node)
        nodeView.onClose = { [weak self] in self?.removeNode(id: node.id, from: self?.currentWorkspace) }
        return nodeView
    }

    // MARK: - 节点删除

    func removeNode(id: UUID, from workspace: WorkspaceManager?) {
        canvas?.removeNodeView(id: id)

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

        terminalViews.removeValue(forKey: id)
        noteViewControllers.removeValue(forKey: id)
        portalViews.removeValue(forKey: id)
        fileTreeViews.removeValue(forKey: id)
        textViews.removeValue(forKey: id)
        drawingViews.removeValue(forKey: id)
        renderedNodeIds.remove(id)
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

    // MARK: - 节点锁定 + 激活 + 复制回调

    private func setupLockCallback(nodeView: BaseNodeView, node: CanvasNode) {
        nodeView.onLockToggle = { [weak self] isLocked in
            guard let self else { return }
            if let idx = self.currentWorkspace?.nodes.firstIndex(where: { $0.id == node.id }) {
                self.currentWorkspace?.nodes[idx].isLocked = isLocked
                self.saveWorkspace()
            }
        }

        // 点击节点时将其 zIndex 提升到最顶层
        nodeView.onActivated = { [weak self] in
            guard let self, let ws = self.currentWorkspace else { return }
            let maxZ = ws.nodes.map { $0.zIndex }.max() ?? 0
            if let idx = ws.nodes.firstIndex(where: { $0.id == node.id }),
               ws.nodes[idx].zIndex < maxZ {
                ws.nodes[idx].zIndex = maxZ + 1
            }
        }

        // 点击节点时通知画布更新选中状态
        nodeView.onNodeClicked = { [weak self, weak nodeView] event in
            guard let canvas = self?.canvas else { return }
            let nodeId = node.id
            if event.modifierFlags.contains(.command) {
                // ⌘+点击：切换选中（多选）
                if canvas.selectedNodeIds.contains(nodeId) {
                    canvas.selectedNodeIds.remove(nodeId)
                } else {
                    canvas.selectedNodeIds.insert(nodeId)
                }
            } else {
                // 普通点击：如果节点已在选中集合中（批量选中），保持选中状态（支持批量拖动）；
                // 如果节点不在选中集合中，执行单选
                if !canvas.selectedNodeIds.contains(nodeId) {
                    canvas.selectedNodeIds = [nodeId]
                }
            }
        }

        // Option+拖拽复制节点
        nodeView.onOptionDragDuplicate = { [weak self] in
            self?.duplicateNode(id: node.id)
        }

        // 右键菜单"复制节点"
        nodeView.onDuplicate = { [weak self] in
            self?.duplicateNode(id: node.id)
        }

        // 右键菜单"创建连接"：选中当前节点并激活连线模式
        nodeView.onConnect = { [weak self] in
            guard let self, let canvas = self.canvas else { return }
            canvas.selectedNodeIds = [node.id]
            canvas.connectingFromNodeId = node.id
            canvas.isInConnectingMode = true
        }
    }

    /// 复制指定节点（Option+拖拽 / 右键菜单共用）
    private func duplicateNode(id: UUID) {
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

    // MARK: - Text 节点

    private func makeTextView(node: CanvasNode, tc: TextContent) -> TextNodeView {
        let nodeView = TextNodeView()
        nodeView.nodeId = node.id
        nodeView.title = "Text"
        nodeView.isLocked = node.isLocked
        nodeView.configure(
            text: tc.text,
            fontSize: tc.fontSize,
            fontWeight: tc.fontWeight,
            color: tc.color,
            alignment: tc.alignment
        )

        nodeView.onTextChanged = { [weak self] newText in
            guard let self, let ws = self.currentWorkspace,
                  let idx = ws.nodes.firstIndex(where: { $0.id == node.id }),
                  case .text(var content) = ws.nodes[idx].content else { return }
            content.text = newText
            ws.nodes[idx].content = .text(content)
            self.saveWorkspace()
        }

        textViews[node.id] = nodeView
        setupLockCallback(nodeView: nodeView, node: node)
        nodeView.onClose = { [weak self] in self?.removeNode(id: node.id, from: self?.currentWorkspace) }
        return nodeView
    }

    // MARK: - Drawing 节点

    private func makeDrawingView(node: CanvasNode, dc: DrawingContent) -> DrawingNodeView {
        let nodeView = DrawingNodeView()
        nodeView.nodeId = node.id
        nodeView.title = "Drawing"
        nodeView.isLocked = node.isLocked
        nodeView.configure(strokes: dc.strokes, backgroundColor: dc.backgroundColor)

        nodeView.onStrokesChanged = { [weak self] newStrokes in
            guard let self, let ws = self.currentWorkspace,
                  let idx = ws.nodes.firstIndex(where: { $0.id == node.id }),
                  case .drawing(var content) = ws.nodes[idx].content else { return }
            content.strokes = newStrokes
            ws.nodes[idx].content = .drawing(content)
            self.saveWorkspace()
        }

        drawingViews[node.id] = nodeView
        setupLockCallback(nodeView: nodeView, node: node)
        nodeView.onClose = { [weak self] in self?.removeNode(id: node.id, from: self?.currentWorkspace) }
        return nodeView
    }

    private func typeLabel(_ content: NodeContent) -> String {
        switch content {
        case .terminal: return "terminal"
        case .stickyNote: return "note"
        case .portal: return "portal"
        case .fileTree: return "fileTree"
        case .text: return "text"
        case .drawing: return "drawing"
        }
    }
}
