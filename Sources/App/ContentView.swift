import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showCreateWorkspace = false
    @State private var selectedWorkspaceId: UUID?

    var body: some View {
        if !appState.hasCompletedOnboarding {
            OnboardingView(hasCompleted: Binding(
                get: { appState.hasCompletedOnboarding },
                set: { done in
                    appState.hasCompletedOnboarding = done
                    appState.forceSave(cleanShutdown: false)
                }
            ))
        } else {
            mainView
        }
    }

    @State private var showLoadError = false

    @ViewBuilder
    private var mainView: some View {
        NavigationSplitView {
            WorkspaceSidebarView(
                selectedId: $selectedWorkspaceId,
                showCreate: $showCreateWorkspace
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            if let id = selectedWorkspaceId,
               let ws = appState.workspaces.first(where: { $0.id == id }) {
                WorkspaceCanvasView(
                    workspace: ws,
                    backgroundMode: appState.preferences.canvasBackground
                )
            } else {
                EmptyCanvasPlaceholder()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showCreateWorkspace) {
            CreateWorkspaceSheet()
        }
        .onAppear {
            selectedWorkspaceId = appState.activeWorkspaceId
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCreateWorkspace)) { _ in
            showCreateWorkspace = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextWorkspace)) { _ in
            navigateWorkspace(direction: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .prevWorkspace)) { _ in
            navigateWorkspace(direction: -1)
        }
        .onAppear {
            if !appState.loadErrors.isEmpty { showLoadError = true }
        }
        .alert("部分工作区加载失败", isPresented: $showLoadError) {
            Button("好") { showLoadError = false }
        } message: {
            Text(appState.loadErrors.joined(separator: "\n"))
        }
    }  // end mainView

    private func navigateWorkspace(direction: Int) {
        let entries = appState.manifest.workspaces
        guard !entries.isEmpty else { return }
        if let current = selectedWorkspaceId,
           let idx = entries.firstIndex(where: { $0.id == current }) {
            let next = (idx + direction + entries.count) % entries.count
            selectedWorkspaceId = entries[next].id
        } else {
            selectedWorkspaceId = entries.first?.id
        }
        appState.activeWorkspaceId = selectedWorkspaceId
    }
}

// MARK: - 工作区画布视图

struct WorkspaceCanvasView: View {
    @Environment(AppState.self) private var appState
    @Bindable var workspace: WorkspaceManager
    var backgroundMode: String
    @State private var canvasOrigin: CGPoint = Constants.canvasInitialOrigin
    @State private var zoom: CGFloat = 1.0
    @State private var isConnecting = false
    @State private var activeDrawingTool: String? = nil
    @State private var showFloorOverview = false
    @State private var terminalToEdit: (nodeId: UUID, content: TerminalContent)? = nil
    @State private var selectedNodeIds: Set<UUID> = []
    @State private var selectedNodeScreenFrame: CGRect? = nil
    @State private var showMinimap = false

    var body: some View {
        ZStack(alignment: .top) {
            canvasBody

            // 顶部工具栏区域：一级工具栏 + 选中时的二级操作栏
            VStack(spacing: 6) {
                // 一级浮动工具栏
                CanvasToolbar(workspace: workspace, isConnecting: $isConnecting, activeDrawingTool: $activeDrawingTool)

                // 二级操作工具栏（选中节点时显示，固定在一级工具栏正下方）
                if !selectedNodeIds.isEmpty {
                    NodeContextToolbar(
                        onEdit: { editSelectedNode() },
                        onConnect: { startConnectionFromSelected() },
                        onRefresh: { /* 预留刷新操作 */ },
                        onDelete: { deleteSelectedNodes() }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut(duration: 0.15), value: selectedNodeIds)
                }
            }
            .zIndex(100)
        }
    }

    @ViewBuilder
    private var canvasBody: some View {
        ZStack {
            CanvasViewportRepresentable(
                canvasOrigin: $canvasOrigin,
                zoom: $zoom,
                backgroundMode: backgroundMode,
                workspace: workspace,
                isConnecting: isConnecting,
                isDrawingMode: activeDrawingTool != nil,
                drawingNodeType: activeDrawingTool ?? "terminal",
                onViewportChanged: { origin, z in
                    canvasOrigin = origin
                    zoom = z
                    workspace.canvasOrigin = origin
                    workspace.canvasZoom = z
                },
                onDeleteSelectedNodes: {
                    // CanvasNodeRenderer 通过 onClose 回调处理节点删除
                },
                onNodeJumpNumbersRequested: { _ in
                    // 数字徽章由 TerminalNodeView 自行管理
                },
                onConnectionCreated: { idA, idB in
                    // 根据节点内容类型选择正确的连接类型
                    let typeA = workspace.nodes.first { $0.id == idA }.map { contentTypeName($0.content) }
                    let typeB = workspace.nodes.first { $0.id == idB }.map { contentTypeName($0.content) }
                    let cm = ConnectionManager.shared

                    switch (typeA, typeB) {
                    case ("terminal", "terminal"):
                        let conn = cm.connectTerminals(idA: idA, idB: idB, serverPort: InterAgentServer.shared.port)
                        workspace.addConnection(conn)
                    case ("terminal", "stickyNote"), ("stickyNote", "terminal"):
                        let termId = typeA == "terminal" ? idA : idB
                        let noteId = typeA == "stickyNote" ? idA : idB
                        let conn = cm.connectTerminalToNote(terminalId: termId, noteNodeId: noteId)
                        workspace.addNoteConnection(conn)
                    case ("terminal", "portal"), ("portal", "terminal"):
                        let termId = typeA == "terminal" ? idA : idB
                        let portId = typeA == "portal" ? idA : idB
                        let conn = cm.connectTerminalToPortal(terminalId: termId, portalNodeId: portId)
                        workspace.addPortalConnection(conn)
                    case ("stickyNote", "stickyNote"):
                        let conn = NoteToNoteConnection(noteNodeIdA: idA, noteNodeIdB: idB)
                        workspace.noteToNoteConnections.append(conn)
                    case ("portal", "portal"):
                        let conn = PortalToPortalConnection(portalIdA: idA, portalIdB: idB)
                        workspace.addPortalToPortalConnection(conn)
                        PortalWebViewStore.shared.shareSession(portalIdA: idA, portalIdB: idB)
                    default:
                        break
                    }
                    Task { try? await workspace.save() }
                    isConnecting = false
                },
                onNodeDrawn: { nodeType, canvasRect in
                    handleNodeDrawn(nodeType: nodeType, frame: canvasRect)
                },
                onSelectionChanged: { ids, frame in
                    selectedNodeIds = ids
                    selectedNodeScreenFrame = frame
                },
                onFilesDropped: { paths, canvasPoint in
                    handleFilesDropped(paths: paths, at: canvasPoint)
                },
                rolePresets: appState.preferences.rolePresets
            )
            .ignoresSafeArea()

            // 底部右下角控件组
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    Spacer()

                    // 底部右侧控件组
                    HStack(spacing: 8) {
                        // Floor 按钮
                        Button {
                            showFloorOverview = true
                        } label: {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 14))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                        .clipShape(Circle())
                        .help("Floors")

                        // 缩略图按钮
                        Button {
                            showMinimap.toggle()
                        } label: {
                            Image(systemName: "map")
                                .font(.system(size: 14))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                        .clipShape(Circle())
                        .help("画布缩略图")
                        .popover(isPresented: $showMinimap, arrowEdge: .top) {
                            CanvasMinimapPopover(
                                nodes: workspace.nodes,
                                canvasOrigin: canvasOrigin,
                                zoom: zoom,
                                onJumpTo: { targetPoint in
                                    // 通过 Notification 触发 CanvasViewportView 平滑动画跳转
                                    NotificationCenter.default.post(
                                        name: .canvasJumpToOrigin,
                                        object: nil,
                                        userInfo: ["origin": targetPoint]
                                    )
                                    showMinimap = false
                                }
                            )
                        }

                        // Zoom 控件
                        HStack(spacing: 0) {
                            Button {
                                NotificationCenter.default.post(name: .canvasZoomOut, object: nil)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Text("\(Int(zoom * 100))%")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .frame(minWidth: 40)

                            Button {
                                NotificationCenter.default.post(name: .canvasZoomIn, object: nil)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(12)
                }
            }
        }
        .onAppear {
            canvasOrigin = workspace.canvasOrigin
            zoom = workspace.canvasZoom
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFloorOverview)) { _ in
            showFloorOverview = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .maestroRecruited)) { notif in
            handleMaestroRecruited(notif: notif)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editTerminalRequested)) { notif in
            if let nodeId = notif.userInfo?["nodeId"] as? UUID,
               let tc = notif.userInfo?["terminalContent"] as? TerminalContent {
                terminalToEdit = (nodeId: nodeId, content: tc)
            }
        }
        .sheet(item: Binding(
            get: { terminalToEdit.map { EditTerminalItem(id: $0.nodeId, content: $0.content) } },
            set: { if $0 == nil { terminalToEdit = nil } }
        )) { item in
            EditTerminalSheet(nodeId: item.id, content: item.content, workspace: workspace) {
                terminalToEdit = nil
            }
        }
        .sheet(isPresented: $showFloorOverview) {
            FloorOverviewView(workspace: workspace)
        }
        .sheet(isPresented: $showTerminalSheetForDrawing) {
            NewTerminalSheet(
                initialPresets: appState.preferences.agentPresets.filter { $0.isActive },
                initialRoles: appState.preferences.rolePresets,
                defaultWorkingDirectory: workspace.workingDirectory
            ) { preset, role, isManager, workDir in
                createTerminalAtFrame(showTerminalDrawnFrame, preset: preset, role: role, isManager: isManager, workingDirectory: workDir)
            }
        }
        .sheet(isPresented: $showPortalSheetForDrawing) {
            NewPortalSheet { url in
                createPortalAtFrame(showPortalDrawnFrame, url: url)
            }
        }
        .autosave(workspace: workspace)
    }

    // MARK: - 拖拽绘制创建节点

    private func handleNodeDrawn(nodeType: String, frame: CGRect) {
        switch nodeType {
        case "terminal":
            // Terminal 需要弹 sheet 选择 Agent 预设
            showTerminalDrawnFrame = frame
            showTerminalSheetForDrawing = true
        case "stickyNote":
            createNoteAtFrame(frame)
        case "portal":
            showPortalDrawnFrame = frame
            showPortalSheetForDrawing = true
        case "fileTree":
            createFileTreeAtFrame(frame)
        default:
            break
        }
        // 绘制完成后退出绘制模式
        activeDrawingTool = nil
    }

    private func createNoteAtFrame(_ frame: CGRect) {
        let name = "Note-\(UUID().uuidString.prefix(6))"
        let fileName = "\(name).md"
        var nc = StickyNoteContent(name: name)
        nc.fileName = fileName
        let node = CanvasNode(
            frame: frame,
            content: .stickyNote(nc)
        )
        let filePath = PersistenceManager.shared.notesDirURL(workspaceId: workspace.id)
            .appendingPathComponent(fileName).path
        try? FileManager.default.createDirectory(
            atPath: PersistenceManager.shared.notesDirURL(workspaceId: workspace.id).path,
            withIntermediateDirectories: true
        )
        try? "".write(toFile: filePath, atomically: true, encoding: .utf8)
        NoteRegistry.shared.register(name: name, filePath: filePath, nodeId: node.id)
        workspace.addNode(node)
        Task { try? await workspace.save() }
    }

    private func createFileTreeAtFrame(_ frame: CGRect) {
        let path = workspace.workingDirectory
        let fc = FileTreeContent(name: URL(fileURLWithPath: path).lastPathComponent, rootPath: path)
        let node = CanvasNode(
            frame: frame,
            content: .fileTree(fc)
        )
        workspace.addNode(node)
        Task { try? await workspace.save() }
    }

    private func createTerminalAtFrame(_ frame: CGRect, preset: AgentPreset, role: RolePreset?, isManager: Bool, workingDirectory: String? = nil) {
        let dir = workingDirectory ?? workspace.workingDirectory
        var tc = TerminalContent(
            name: preset.name,
            agentType: preset.agentType,
            command: preset.command,
            workingDirectory: dir
        )
        tc.isManager = isManager
        let node = CanvasNode(
            id: tc.id,
            frame: frame,
            content: .terminal(tc)
        )
        workspace.addNode(node)
        let wsId = workspace.id
        Task { @MainActor in
            _ = TerminalManager.shared.createTerminal(
                id: tc.id, workingDirectory: tc.workingDirectory,
                preset: preset, role: role, workspaceId: wsId
            )
        }
        Task { try? await workspace.save() }
    }

    private func createPortalAtFrame(_ frame: CGRect, url: String) {
        let pc = PortalContent(name: "Portal", url: url)
        let node = CanvasNode(
            frame: frame,
            content: .portal(pc)
        )
        workspace.addNode(node)
        Task { try? await workspace.save() }
    }

    /// 处理从 Finder 拖入的 .md/.markdown/.txt 文件，创建 Note 节点（storageMode = .custom）
    private func handleFilesDropped(paths: [String], at canvasOriginPoint: CGPoint) {
        var offsetY: CGFloat = 0
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let name = url.deletingPathExtension().lastPathComponent
            var nc = StickyNoteContent(name: name)
            nc.fileName = url.lastPathComponent
            nc.storageMode = .custom(path: path)
            let frame = CGRect(
                x: canvasOriginPoint.x,
                y: canvasOriginPoint.y - offsetY,
                width: 320,
                height: 240
            )
            let node = CanvasNode(frame: frame, content: .stickyNote(nc))
            NoteRegistry.shared.register(name: name, filePath: path, nodeId: node.id)
            workspace.addNode(node)
            offsetY += 260  // 多文件垂直排列，间距 20pt
        }
        Task { try? await workspace.save() }
    }

    @State private var showTerminalDrawnFrame: CGRect = .zero
    @State private var showTerminalSheetForDrawing = false
    @State private var showPortalDrawnFrame: CGRect = .zero
    @State private var showPortalSheetForDrawing = false

    // MARK: - Maestro Recruit 处理

    private func handleMaestroRecruited(notif: Notification) {
        guard let info = notif.userInfo,
              let maestroId = info["maestroId"] as? UUID,
              var recruitNode = info["recruitNode"] as? CanvasNode,
              let conn = info["connection"] as? TerminalConnection,
              let connectedIds = info["connectedIds"] as? [UUID] else { return }

        // 计算节点位置：在 Maestro 下方均匀排列
        if let maestroNode = workspace.nodes.first(where: { $0.id == maestroId }) {
            let existingCount = CGFloat(connectedIds.filter { id in
                workspace.nodes.contains { $0.id == id }
            }.count)
            let w: CGFloat = 600, h: CGFloat = 400, gap: CGFloat = 20
            recruitNode.frame = CGRect(
                x: maestroNode.frame.minX + existingCount * (w + gap),
                y: maestroNode.frame.maxY + 40,
                width: w, height: h
            )
        }

        workspace.addNode(recruitNode)
        workspace.addConnection(conn)
        Task { try? await workspace.save() }
    }

    // MARK: - 浮动工具栏操作

    private func duplicateSelectedNodes() {
        for id in selectedNodeIds {
            guard let original = workspace.nodes.first(where: { $0.id == id }) else { continue }
            var copy = original
            copy.id = UUID()
            copy.frame = copy.frame.offsetBy(dx: 30, dy: 30)
            copy.zIndex = (workspace.nodes.map { $0.zIndex }.max() ?? 0) + 1
            if case .terminal(var tc) = copy.content {
                tc.id = UUID()
                copy.content = .terminal(tc)
            }
            workspace.addNode(copy)
        }
        Task { try? await workspace.save() }
    }

    private func deleteSelectedNodes() {
        for id in selectedNodeIds {
            workspace.removeNode(id: id)
        }
        selectedNodeIds.removeAll()
        selectedNodeScreenFrame = nil
        Task { try? await workspace.save() }
    }

    private func lockSelectedNodes() {
        for id in selectedNodeIds {
            if let idx = workspace.nodes.firstIndex(where: { $0.id == id }) {
                workspace.nodes[idx].isLocked.toggle()
            }
        }
        Task { try? await workspace.save() }
    }

    /// 编辑选中的节点（对 Terminal 弹出编辑 Sheet）
    private func editSelectedNode() {
        guard let firstId = selectedNodeIds.first,
              let node = workspace.nodes.first(where: { $0.id == firstId }),
              case .terminal(let tc) = node.content else { return }
        terminalToEdit = (nodeId: firstId, content: tc)
    }

    /// 从选中节点开始创建连线
    private func startConnectionFromSelected() {
        guard !selectedNodeIds.isEmpty else { return }
        isConnecting = true
    }
}

// MARK: - 节点类型辅助

private func contentTypeName(_ content: NodeContent) -> String {
    switch content {
    case .terminal:  return "terminal"
    case .stickyNote: return "stickyNote"
    case .portal:    return "portal"
    case .fileTree:  return "fileTree"
    }
}

// MARK: - 空画布占位

struct EmptyCanvasPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.dashed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("从这里开始")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("在侧边栏创建一个工作区")
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Autosave Modifier

/// 自动保存修饰符：每 30 秒定时保存 + 视图消失时立即保存（符合 NFR5）
private struct AutosaveModifier: ViewModifier {
    let workspace: WorkspaceManager
    /// 30 秒定时器
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content
            .onReceive(timer) { _ in
                Task { try? await workspace.save() }
            }
            .onDisappear {
                Task { try? await workspace.save() }
            }
    }
}

private extension View {
    func autosave(workspace: WorkspaceManager) -> some View {
        modifier(AutosaveModifier(workspace: workspace))
    }
}

// MARK: - 选中节点浮动工具栏

struct NodeContextToolbar: View {
    let onEdit: () -> Void
    let onConnect: () -> Void
    let onRefresh: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            contextButton(icon: "square.and.pencil", tooltip: "编辑", action: onEdit)
            contextButton(icon: "point.3.connected.trianglepath.dotted", tooltip: "连接到终端", action: onConnect)
            contextButton(icon: "arrow.triangle.2.circlepath", tooltip: "刷新", action: onRefresh)
            contextButton(icon: "trash", tooltip: "删除", action: onDelete)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            Capsule()
                .fill(.white)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .overlay(
                    Capsule()
                        .strokeBorder(Color(white: 0.9), lineWidth: 0.5)
                )
        }
    }

    private func contextButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(white: 0.35))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

// MARK: - 画布缩略图弹层

struct CanvasMinimapPopover: View {
    let nodes: [CanvasNode]
    let canvasOrigin: CGPoint
    let zoom: CGFloat
    let onJumpTo: (CGPoint) -> Void

    /// 缩略图固定尺寸
    private let mapSize = CGSize(width: 280, height: 180)

    var body: some View {
        VStack(spacing: 0) {
            if nodes.isEmpty {
                Text("画布为空")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: mapSize.width, height: mapSize.height)
            } else {
                minimapCanvas
            }
        }
        .padding(12)
    }

    private var minimapCanvas: some View {
        let bounds = computeBounds()
        let scale = computeScale(bounds: bounds)

        return ZStack(alignment: .topLeading) {
            // 浅灰背景（画布区域）
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.96))
                .frame(width: mapSize.width, height: mapSize.height)

            // 节点色块
            ForEach(nodes, id: \.id) { node in
                let rect = scaledRect(for: node.frame, bounds: bounds, scale: scale)
                Button {
                    // 点击节点 → 将画布定位使该节点居中
                    let viewportW: CGFloat = 800 / zoom
                    let viewportH: CGFloat = 600 / zoom
                    let target = CGPoint(
                        x: node.frame.midX - viewportW / 2,
                        y: node.frame.midY - viewportH / 2
                    )
                    onJumpTo(target)
                } label: {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(nodeColor(for: node.content))
                        .frame(width: max(rect.width, 6), height: max(rect.height, 4))
                        .offset(x: rect.minX, y: rect.minY)
                }
                .buttonStyle(.plain)
            }

            // 当前视口指示框
            let viewportRect = scaledViewportRect(bounds: bounds, scale: scale)
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.blue.opacity(0.6), lineWidth: 1.5)
                .frame(width: viewportRect.width, height: viewportRect.height)
                .offset(x: viewportRect.minX, y: viewportRect.minY)
        }
        .frame(width: mapSize.width, height: mapSize.height)
        .clipped()
    }

    // MARK: - 坐标计算

    /// 计算所有节点的包围盒（含一些 padding）
    private func computeBounds() -> CGRect {
        guard !nodes.isEmpty else { return .zero }
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for node in nodes {
            minX = min(minX, node.frame.minX)
            minY = min(minY, node.frame.minY)
            maxX = max(maxX, node.frame.maxX)
            maxY = max(maxY, node.frame.maxY)
        }
        // 添加 padding
        let pad: CGFloat = 100
        return CGRect(x: minX - pad, y: minY - pad,
                      width: maxX - minX + pad * 2,
                      height: maxY - minY + pad * 2)
    }

    /// 计算缩放比例（保持纵横比 fit 到 mapSize）
    private func computeScale(bounds: CGRect) -> CGFloat {
        guard bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(mapSize.width / bounds.width, mapSize.height / bounds.height)
    }

    /// 将画布坐标映射到缩略图坐标
    private func scaledRect(for frame: CGRect, bounds: CGRect, scale: CGFloat) -> CGRect {
        let x = (frame.minX - bounds.minX) * scale
        let y = (frame.minY - bounds.minY) * scale
        let w = frame.width * scale
        let h = frame.height * scale
        // 居中偏移
        let totalW = bounds.width * scale
        let totalH = bounds.height * scale
        let offsetX = (mapSize.width - totalW) / 2
        let offsetY = (mapSize.height - totalH) / 2
        return CGRect(x: x + offsetX, y: y + offsetY, width: w, height: h)
    }

    /// 当前视口在缩略图中的位置
    private func scaledViewportRect(bounds: CGRect, scale: CGFloat) -> CGRect {
        let vpW: CGFloat = 800 / zoom  // 估算视口宽度
        let vpH: CGFloat = 600 / zoom  // 估算视口高度
        let vpFrame = CGRect(x: canvasOrigin.x, y: canvasOrigin.y, width: vpW, height: vpH)
        return scaledRect(for: vpFrame, bounds: bounds, scale: scale)
    }

    /// 根据节点类型返回对应颜色（与截图一致）
    private func nodeColor(for content: NodeContent) -> Color {
        switch content {
        case .terminal:
            return Color.blue                          // 蓝色（终端）
        case .stickyNote:
            return Color(red: 0.6, green: 0.88, blue: 0.88)  // 浅青色（笔记）
        case .portal:
            return Color(red: 1.0, green: 0.92, blue: 0.6)   // 浅黄色（Portal）
        case .fileTree:
            return Color(red: 1.0, green: 0.82, blue: 0.6)   // 浅橙色（文件树）
        }
    }
}
