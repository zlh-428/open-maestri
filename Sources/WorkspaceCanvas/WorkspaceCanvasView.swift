import SwiftUI

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
    @State private var showAssignRoleSheet = false
    @State private var assignRoleNodeId: UUID? = nil


    var body: some View {
        ZStack(alignment: .top) {
            canvasBody

            // 顶部浮动工具栏区域
            toolbarOverlay
        }
    }

    /// 当前是否全屏
    private var isFullScreen: Bool { WindowStateObserver.shared.isFullScreen }

    /// 顶部工具栏覆盖层
    @ViewBuilder
    private var toolbarOverlay: some View {
        VStack(spacing: 0) {
            // 浮动工具栏（距窗口顶部 8px）
            CanvasToolbar(workspace: workspace, isConnecting: $isConnecting, activeDrawingTool: $activeDrawingTool)
                .padding(.top, 8)

            // 二级操作工具栏（选中节点时显示）
            // 与一级工具栏间距加大
            Spacer().frame(height: 12)

            // 仅当选中的节点确实存在于 workspace 中时才显示
            if !selectedNodeIds.isEmpty && selectedNodeIds.contains(where: { id in
                workspace.nodes.contains { $0.id == id }
            }) {
                if selectedNodeContentType == "fileTree" {
                    FileTreeContextToolbar(
                        onRevealInFinder: { revealFileTreeInFinder() },
                        onChangeRoot: { changeFileTreeRoot() },
                        onDelete: { deleteSelectedNodes() }
                    )
                    .fixedSize()
                    .padding(.bottom, 36)
                    .contentShape(Rectangle())
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut(duration: 0.15), value: selectedNodeIds)
                } else if selectedNodeContentType == "stickyNote",
                          let noteId = selectedNodeIds.first {
                    NoteContextToolbar(
                        nodeId: noteId,
                        isFormatted: noteIsPreviewing(nodeId: noteId),
                        onBgColor: { color in setNoteColor(nodeId: noteId, color: color) },
                        onFontSize: { size in setNoteFontSize(nodeId: noteId, size: size) },
                        onConnect: { startConnectionFromSelected() },
                        onToggleFormatted: { toggleNoteFormatted(nodeId: noteId) },
                        onDelete: { deleteSelectedNodes() },
                        onSaveAs: { saveNoteAs(nodeId: noteId) }
                    )
                    .fixedSize()
                    .padding(.bottom, 36)
                    .contentShape(Rectangle())
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut(duration: 0.15), value: selectedNodeIds)
                } else {
                    NodeContextToolbar(
                        onEdit: { editSelectedNode() },
                        onConnect: { startConnectionFromSelected() },
                        onRefresh: { /* 预留刷新操作 */ },
                        onDelete: { deleteSelectedNodes() }
                    )
                    .fixedSize()
                    .padding(.bottom, 36)
                    .contentShape(Rectangle())
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut(duration: 0.15), value: selectedNodeIds)
                }
            }
        }
        .frame(maxWidth: .infinity)
        // 非全屏模式：忽略顶部安全区域，让工具栏延伸到标题栏区域
        // 全屏模式：不忽略安全区域，工具栏在 NavigationSplitView toolbar 下方正常显示
        .modifier(ConditionalIgnoreSafeAreaTop(ignore: !isFullScreen))
        .zIndex(100)
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
                    // 防止同一对节点重复连接
                    let alreadyConnected = workspace.connections.contains {
                        ($0.terminalIdA == idA && $0.terminalIdB == idB) ||
                        ($0.terminalIdA == idB && $0.terminalIdB == idA)
                    } || workspace.noteConnections.contains {
                        ($0.terminalId == idA && $0.noteNodeId == idB) ||
                        ($0.terminalId == idB && $0.noteNodeId == idA)
                    } || workspace.portalConnections.contains {
                        ($0.terminalId == idA && $0.portalNodeId == idB) ||
                        ($0.terminalId == idB && $0.portalNodeId == idA)
                    } || workspace.noteToNoteConnections.contains {
                        ($0.noteNodeIdA == idA && $0.noteNodeIdB == idB) ||
                        ($0.noteNodeIdA == idB && $0.noteNodeIdB == idA)
                    } || workspace.portalToPortalConnections.contains {
                        ($0.portalIdA == idA && $0.portalIdB == idB) ||
                        ($0.portalIdA == idB && $0.portalIdB == idA)
                    }
                    guard !alreadyConnected else {
                        isConnecting = false
                        return
                    }

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
                        let conn = cm.connectNoteToNote(noteNodeIdA: idA, noteNodeIdB: idB)
                        workspace.noteToNoteConnections.append(conn)
                    case ("portal", "portal"):
                        let conn = cm.connectPortalToPortal(portalIdA: idA, portalIdB: idB)
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
                onFilesDroppedOnNode: { paths, nodeId in
                    handleFilesDroppedOnNode(paths: paths, nodeId: nodeId)
                },
                rolePresets: appState.preferences.rolePresets,
                agentPresets: appState.preferences.agentPresets.filter { $0.isActive },
                onCanvasContextCreateNode: { nodeType, canvasPoint in
                    handleCanvasContextCreateNode(nodeType: nodeType, at: canvasPoint)
                },
                onCanvasContextCreateTerminal: { presetIndex, canvasPoint in
                    handleCanvasContextCreateTerminal(presetIndex: presetIndex, at: canvasPoint)
                },
                onCanvasContextPaste: { canvasPoint in
                    handleCanvasContextPaste(at: canvasPoint)
                }
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
                        .help("floor.overview".localized)

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
                        .help("tooltip.minimap".localized)
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
                            .environment(\.locale, LocalizationManager.shared.locale)
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
            preInitializeAllTerminals()
            ConnectionManager.shared.restoreConnections(
                from: workspace,
                serverPort: InterAgentServer.shared.port
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFloorOverview)) { _ in
            showFloorOverview = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .maestroRecruited)) { notif in
            handleMaestroRecruited(notif: notif)
        }
        .onReceive(NotificationCenter.default.publisher(for: .portalCreatedViaCLI)) { notif in
            handlePortalCreatedViaCLI(notif: notif)
        }
        .onReceive(NotificationCenter.default.publisher(for: .portalOpenedNewWindow)) { notif in
            handlePortalOpenedNewWindow(notif: notif)
        }
        .onReceive(NotificationCenter.default.publisher(for: .portalURLDidChange)) { notif in
            handlePortalURLDidChange(notif: notif)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editTerminalRequested)) { notif in
            if let nodeId = notif.userInfo?["nodeId"] as? UUID,
               let tc = notif.userInfo?["terminalContent"] as? TerminalContent {
                terminalToEdit = (nodeId: nodeId, content: tc)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .contextMenuConnect)) { notif in
            if let nodeId = notif.userInfo?["nodeId"] as? UUID {
                selectedNodeIds = [nodeId]
                isConnecting = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .contextMenuAssignRole)) { notif in
            if let nodeId = notif.userInfo?["nodeId"] as? UUID {
                assignRoleNodeId = nodeId
                showAssignRoleSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .contextMenuToggleMaestro)) { notif in
            if let nodeId = notif.userInfo?["nodeId"] as? UUID {
                toggleMaestroMode(nodeId: nodeId)
            }
        }
        .sheet(isPresented: $showAssignRoleSheet) {
            AssignRoleSheet(
                roles: appState.preferences.rolePresets,
                currentRoleId: currentAssignedRoleId,
                onAssign: { role in
                    applyRole(role, toNodeId: assignRoleNodeId)
                    showAssignRoleSheet = false
                },
                onUnassign: {
                    unassignRole(fromNodeId: assignRoleNodeId)
                    showAssignRoleSheet = false
                },
                onDismiss: { showAssignRoleSheet = false }
            )
            .environment(\.locale, LocalizationManager.shared.locale)
        }
        .sheet(item: Binding(
            get: { terminalToEdit.map { EditTerminalItem(id: $0.nodeId, content: $0.content) } },
            set: { if $0 == nil { terminalToEdit = nil } }
        )) { item in
            EditTerminalSheet(nodeId: item.id, content: item.content, workspace: workspace) {
                terminalToEdit = nil
            }
            .environment(\.locale, LocalizationManager.shared.locale)
        }
        .sheet(isPresented: $showFloorOverview) {
            FloorOverviewView(workspace: workspace)
                .environment(\.locale, LocalizationManager.shared.locale)
        }
        .sheet(isPresented: $showTerminalSheetForDrawing) {
            NewTerminalSheet(
                initialPresets: appState.preferences.agentPresets.filter { $0.isActive },
                initialRoles: appState.preferences.rolePresets,
                defaultWorkingDirectory: workspace.workingDirectory
            ) { preset, role, isManager, workDir in
                createTerminalAtFrame(showTerminalDrawnFrame, preset: preset, role: role, isManager: isManager, workingDirectory: workDir)
            }
            .environment(\.locale, LocalizationManager.shared.locale)
        }
        .sheet(isPresented: $showPortalSheetForDrawing) {
            NewPortalSheet { name, url in
                createPortalAtFrame(showPortalDrawnFrame, name: name, url: url)
            }
            .environment(\.locale, LocalizationManager.shared.locale)
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
        case "text":
            createTextAtFrame(frame)
        case "drawing":
            createDrawingAtFrame(frame)
        default:
            break
        }
        // 绘制完成后退出绘制模式
        activeDrawingTool = nil
    }

    private func createNoteAtFrame(_ frame: CGRect) {
        let name = nextNodeName(for: "stickyNote")
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

    private func createTextAtFrame(_ frame: CGRect) {
        let tc = TextContent(text: "")
        let node = CanvasNode(
            frame: frame,
            content: .text(tc)
        )
        workspace.addNode(node)
        Task { try? await workspace.save() }
    }

    private func createDrawingAtFrame(_ frame: CGRect) {
        let dc = DrawingContent()
        let node = CanvasNode(
            frame: frame,
            content: .drawing(dc)
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
                id: tc.id,
                command: preset.command,
                workingDirectory: tc.workingDirectory,
                workspaceId: wsId,
                roleName: role?.name,
                displayName: tc.name
            )
        }
        Task { try? await workspace.save() }
    }

    private func createPortalAtFrame(_ frame: CGRect, name: String, url: String) {
        let portalName = name.isEmpty ? nextNodeName(for: "portal") : name
        let pc = PortalContent(name: portalName, url: url)
        let node = CanvasNode(
            frame: frame,
            content: .portal(pc)
        )
        workspace.addNode(node)
        Task { try? await workspace.save() }
    }

    // MARK: - Canvas Blank Area Context Menu Handlers

    /// 画布空白区域右键菜单：创建指定类型节点
    private func handleCanvasContextCreateNode(nodeType: String, at canvasPoint: CGPoint) {
        let size = defaultNodeSize(for: nodeType)
        let frame = CGRect(
            x: canvasPoint.x - size.width / 2,
            y: canvasPoint.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        switch nodeType {
        case "stickyNote":
            createNoteAtFrame(frame)
        case "fileTree":
            createFileTreeAtFrame(frame)
        case "portal":
            // Portal 需要弹 sheet 输入 URL
            showPortalDrawnFrame = frame
            showPortalSheetForDrawing = true
        case "text":
            createTextAtFrame(frame)
        case "linkedFile":
            // 链接文件：弹出文件选择面板
            createLinkedFileAtFrame(frame)
        default:
            break
        }
    }

    /// 画布空白区域右键菜单：根据预设索引创建终端节点
    private func handleCanvasContextCreateTerminal(presetIndex: Int, at canvasPoint: CGPoint) {
        let activePresets = appState.preferences.agentPresets.filter { $0.isActive }
        guard presetIndex >= 0, presetIndex < activePresets.count else { return }
        let preset = activePresets[presetIndex]
        let size = defaultNodeSize(for: "terminal")
        let frame = CGRect(
            x: canvasPoint.x - size.width / 2,
            y: canvasPoint.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        createTerminalAtFrame(frame, preset: preset, role: nil, isManager: false)
    }

    /// 画布空白区域右键菜单：粘贴
    private func handleCanvasContextPaste(at canvasPoint: CGPoint) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        // 粘贴文本内容为 Note 节点
        let name = "Pasted-\(UUID().uuidString.prefix(6))"
        let fileName = "\(name).md"
        var nc = StickyNoteContent(name: name)
        nc.fileName = fileName
        let size = defaultNodeSize(for: "stickyNote")
        let frame = CGRect(
            x: canvasPoint.x - size.width / 2,
            y: canvasPoint.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        let node = CanvasNode(frame: frame, content: .stickyNote(nc))
        let filePath = PersistenceManager.shared.notesDirURL(workspaceId: workspace.id)
            .appendingPathComponent(fileName).path
        try? FileManager.default.createDirectory(
            atPath: PersistenceManager.shared.notesDirURL(workspaceId: workspace.id).path,
            withIntermediateDirectories: true
        )
        try? text.write(toFile: filePath, atomically: true, encoding: .utf8)
        NoteRegistry.shared.register(name: name, filePath: filePath, nodeId: node.id)
        workspace.addNode(node)
        Task { try? await workspace.save() }
    }

    /// 链接文件：弹出文件选择器并在指定位置创建节点
    private func createLinkedFileAtFrame(_ frame: CGRect) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let name = url.lastPathComponent
                var nc = StickyNoteContent(name: name)
                nc.fileName = url.lastPathComponent
                nc.storageMode = .custom(path: url.path)
                let node = CanvasNode(frame: frame, content: .stickyNote(nc))
                NoteRegistry.shared.register(name: name, filePath: url.path, nodeId: node.id)
                workspace.addNode(node)
                Task { try? await workspace.save() }
            }
        }
    }

    /// 节点类型对应的默认尺寸（复用 CanvasViewportView 的定义）
    private func defaultNodeSize(for nodeType: String) -> CGSize {
        switch nodeType {
        case "terminal": return CGSize(width: 600, height: 400)
        case "stickyNote": return CGSize(width: 300, height: 240)
        case "portal": return CGSize(width: 500, height: 380)
        case "fileTree": return CGSize(width: 360, height: 480)
        case "text": return CGSize(width: 200, height: 60)
        case "linkedFile": return CGSize(width: 300, height: 240)
        default: return CGSize(width: 400, height: 300)
        }
    }

    /// 根据现有同类型节点数量生成递增编号名称（如 "Portal #1", "Note #2"）
    private func nextNodeName(for nodeType: String) -> String {
        let prefix: String
        switch nodeType {
        case "portal": prefix = "Portal"
        case "stickyNote": prefix = "Note"
        case "fileTree": prefix = "File Tree"
        case "text": prefix = "Text"
        case "drawing": prefix = "Drawing"
        default: prefix = "Node"
        }

        // 统计当前画布上同类型节点数量
        let existingCount = workspace.nodes.count { node in
            switch (nodeType, node.content) {
            case ("portal", .portal): return true
            case ("stickyNote", .stickyNote): return true
            case ("fileTree", .fileTree): return true
            case ("text", .text): return true
            case ("drawing", .drawing): return true
            default: return false
            }
        }

        return "\(prefix) #\(existingCount + 1)"
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

    /// 文件拖入节点时的处理
    /// - Terminal 节点：将文件路径写入 PTY（空格分隔，shell 友好转义）
    /// - 其他节点类型：暂不处理
    private func handleFilesDroppedOnNode(paths: [String], nodeId: UUID) {
        guard let node = workspace.nodes.first(where: { $0.id == nodeId }) else { return }
        switch node.content {
        case .terminal(let tc):
            // 将文件路径写入终端 PTY（shell 转义后空格分隔）
            if let provider = TerminalManager.shared.providers[tc.id] {
                let escaped = paths.map { shellEscape($0) }
                provider.write(escaped.joined(separator: " "))
            }
        default:
            break
        }
    }

    /// Shell 路径转义：对包含空格或特殊字符的路径加单引号
    private func shellEscape(_ path: String) -> String {
        let special = CharacterSet(charactersIn: " '\"\\$`!#&|;(){}[]<>?*~")
        if path.unicodeScalars.contains(where: { special.contains($0) }) {
            // 用单引号包裹，内部单引号用 '\'' 转义
            let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
            return "'\(escaped)'"
        }
        return path
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

    // MARK: - Portal CLI 创建处理

    private func handlePortalCreatedViaCLI(notif: Notification) {
        guard let info = notif.userInfo,
              var portalNode = info["portalNode"] as? CanvasNode else { return }
        let callerTerminalId = info["terminalId"] as? UUID

        let defaultSize = CGSize(width: 700, height: 500)
        if let tid = callerTerminalId,
           let callerNode = workspace.nodes.first(where: { $0.id == tid }) {
            portalNode.frame = CGRect(
                x: callerNode.frame.maxX + 40,
                y: callerNode.frame.minY,
                width: defaultSize.width,
                height: defaultSize.height
            )
        } else {
            let origin = workspace.canvasOrigin
            portalNode.frame = CGRect(
                x: origin.x + 200, y: origin.y + 100,
                width: defaultSize.width, height: defaultSize.height
            )
        }

        workspace.addNode(portalNode)

        if let tid = callerTerminalId {
            let conn = ConnectionManager.shared.connectTerminalToPortal(terminalId: tid, portalNodeId: portalNode.id)
            workspace.addPortalConnection(conn)
        }

        Task { try? await workspace.save() }
    }

    private func handlePortalOpenedNewWindow(notif: Notification) {
        guard let info = notif.userInfo,
              let urlString = info["url"] as? String,
              let openerPortalId = info["openerPortalId"] as? UUID else { return }

        let defaultSize = CGSize(width: 700, height: 500)
        let frame: CGRect
        if let openerNode = workspace.nodes.first(where: { $0.id == openerPortalId }) {
            frame = CGRect(
                x: openerNode.frame.maxX + 40,
                y: openerNode.frame.minY,
                width: defaultSize.width,
                height: defaultSize.height
            )
        } else {
            let origin = workspace.canvasOrigin
            frame = CGRect(
                x: origin.x + 200, y: origin.y + 100,
                width: defaultSize.width, height: defaultSize.height
            )
        }

        let portalName = nextNodeName(for: "portal")
        let pc = PortalContent(name: portalName, url: urlString)
        let newNode = CanvasNode(frame: frame, content: .portal(pc))
        workspace.addNode(newNode)

        let conn = ConnectionManager.shared.connectPortalToPortal(portalIdA: openerPortalId, portalIdB: newNode.id)
        workspace.addPortalToPortalConnection(conn)

        Task { try? await workspace.save() }
    }

    private func handlePortalURLDidChange(notif: Notification) {
        guard let info = notif.userInfo,
              let portalId = info["portalId"] as? UUID,
              let url = info["url"] as? String,
              let idx = workspace.nodes.firstIndex(where: { $0.id == portalId }),
              case .portal(var pc) = workspace.nodes[idx].content else { return }
        guard pc.currentURL != url else { return }
        pc.currentURL = url
        workspace.nodes[idx].content = .portal(pc)
        Task { try? await workspace.save() }
    }

    // MARK: - 终端预初始化

    /// 进入工作区时立即并行初始化所有终端（PTY 同时 fork）
    /// 对标 Maestri：所有终端并行启动，5s 内全部就绪
    @MainActor
    private func preInitializeAllTerminals() {
        let nodes = workspace.nodes
        let wsId = workspace.id
        let wsDir = workspace.workingDirectory
        let rolePresets = appState.preferences.rolePresets

        // 筛出需要初始化的终端节点
        let pending = nodes.filter { node -> Bool in
            guard case .terminal(let tc) = node.content else { return false }
            return TerminalManager.shared.terminals[tc.id] == nil
        }
        guard !pending.isEmpty else { return }

        // 并行启动所有终端（PTY fork 本身很轻量，不阻塞 UI 线程）
        for node in pending {
            guard case .terminal(let tc) = node.content else { continue }
            guard TerminalManager.shared.terminals[tc.id] == nil else { continue }
            guard TerminalManager.shared.providers[tc.id] == nil else { continue }

            let role: RolePreset? = tc.assignedRoleId.flatMap { roleId in
                rolePresets.first { $0.id == roleId }
            }
            _ = TerminalManager.shared.createTerminal(
                id: tc.id,
                command: tc.command,
                workingDirectory: tc.workingDirectory.isEmpty ? wsDir : tc.workingDirectory,
                workspaceId: wsId,
                roleName: role?.name,
                displayName: tc.name
            )
        }
    }

    // MARK: - 浮动工具栏操作

    // MARK: Note 工具栏辅助方法

    private func noteIsPreviewing(nodeId: UUID) -> Bool {
        guard let node = workspace.nodes.first(where: { $0.id == nodeId }),
              case .stickyNote(let nc) = node.content else { return false }
        return nc.isPreviewing
    }

    private func toggleNoteFormatted(nodeId: UUID) {
        guard let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .stickyNote(var nc) = workspace.nodes[idx].content else { return }
        nc.isPreviewing.toggle()
        workspace.nodes[idx].content = .stickyNote(nc)
        NotificationCenter.default.post(
            name: .noteFormattedToggled,
            object: nil,
            userInfo: ["nodeId": nodeId, "isPreviewing": nc.isPreviewing]
        )
        Task { try? await workspace.save() }
    }

    private func setNoteColor(nodeId: UUID, color: String) {
        guard let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .stickyNote(var nc) = workspace.nodes[idx].content else { return }
        nc.color = color
        let newContent = NodeContent.stickyNote(nc)
        workspace.nodes[idx].content = newContent
        NotificationCenter.default.post(
            name: .canvasNodeContentChanged,
            object: nil,
            userInfo: ["nodeId": nodeId, "content": newContent]
        )
        Task { try? await workspace.save() }
    }

    private func setNoteFontSize(nodeId: UUID, size: Int) {
        guard let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .stickyNote(var nc) = workspace.nodes[idx].content else { return }
        nc.fontSize = size
        workspace.nodes[idx].content = .stickyNote(nc)
        Task { try? await workspace.save() }
    }

    private func saveNoteAs(nodeId: UUID) {
        guard let node = workspace.nodes.first(where: { $0.id == nodeId }),
              case .stickyNote(let nc) = node.content else { return }
        let filePath: String
        switch nc.storageMode {
        case .managed:
            let dir = PersistenceManager.shared.notesDirURL(workspaceId: workspace.id)
            filePath = dir.appendingPathComponent(nc.fileName ?? "\(nodeId).md").path
        case .custom(let path):
            filePath = path
        }
        guard let content = try? NoteFileManager.shared.read(filePath: filePath) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = nc.fileName ?? "note.md"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

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
                let newLocked = !workspace.nodes[idx].isLocked
                workspace.nodes[idx].isLocked = newLocked
                NotificationCenter.default.post(
                    name: .canvasNodeLockChanged,
                    object: nil,
                    userInfo: ["nodeId": id, "isLocked": newLocked]
                )
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

    /// 切换终端节点的 Maestro 模式
    private func toggleMaestroMode(nodeId: UUID?) {
        guard let nodeId,
              let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .terminal(var tc) = workspace.nodes[idx].content else { return }
        tc.isManager = !tc.isManager
        let newContent = NodeContent.terminal(tc)
        workspace.nodes[idx].content = newContent
        NotificationCenter.default.post(
            name: .canvasNodeContentChanged,
            object: nil,
            userInfo: ["nodeId": nodeId, "content": newContent]
        )
        Task { try? await workspace.save() }
    }

    /// 当前要分配角色的节点已有的角色 ID
    private var currentAssignedRoleId: UUID? {
        guard let nodeId = assignRoleNodeId,
              let node = workspace.nodes.first(where: { $0.id == nodeId }),
              case .terminal(let tc) = node.content else { return nil }
        return tc.assignedRoleId
    }

    /// 为终端节点分配角色，同时调用 RoleInjector 写入文件
    private func applyRole(_ role: RolePreset, toNodeId nodeId: UUID?) {
        guard let nodeId,
              let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .terminal(var tc) = workspace.nodes[idx].content else { return }
        tc.assignedRoleId = role.id
        tc.color = role.color
        tc.icon = role.icon
        let newContent = NodeContent.terminal(tc)
        workspace.nodes[idx].content = newContent
        NotificationCenter.default.post(
            name: .canvasNodeContentChanged,
            object: nil,
            userInfo: ["nodeId": nodeId, "content": newContent]
        )

        // 写入 CLAUDE.md / AGENTS.md 到角色目录
        let workDir = tc.workingDirectory.isEmpty ? workspace.workingDirectory : tc.workingDirectory
        RoleInjector.shared.prepareRoleDirectory(
            roleId: role.id,
            rolePrompt: role.prompt,
            workingDirectory: workDir
        )

        // 重启终端以应用新角色（在角色目录下启动）
        restartTerminalWithRole(terminalId: tc.id, role: role, workingDirectory: workDir)

        Task { try? await workspace.save() }
    }

    /// 取消终端节点的角色分配
    private func unassignRole(fromNodeId nodeId: UUID?) {
        guard let nodeId,
              let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .terminal(var tc) = workspace.nodes[idx].content else { return }
        let oldRoleId = tc.assignedRoleId
        tc.assignedRoleId = nil
        // 恢复默认颜色和图标
        tc.color = "#007AFF"
        tc.icon = "terminal"
        let unassignedContent = NodeContent.terminal(tc)
        workspace.nodes[idx].content = unassignedContent
        NotificationCenter.default.post(
            name: .canvasNodeContentChanged,
            object: nil,
            userInfo: ["nodeId": nodeId, "content": unassignedContent]
        )

        // 清理角色目录（如果没有其他终端使用该角色）
        if let roleId = oldRoleId {
            let stillUsed = workspace.nodes.contains { node in
                if case .terminal(let otherTc) = node.content, otherTc.assignedRoleId == roleId, node.id != nodeId {
                    return true
                }
                return false
            }
            if !stillUsed {
                // 不删除角色目录，因为其他工作区可能使用
            }
        }

        // 重启终端在原始工作目录
        restartTerminalInOriginalDir(terminalId: tc.id, workingDirectory: tc.workingDirectory)

        Task { try? await workspace.save() }
    }

    /// 重启终端并应用角色
    private func restartTerminalWithRole(terminalId: UUID, role: RolePreset, workingDirectory: String) {
        // 先移除旧终端
        TerminalManager.shared.removeTerminal(id: terminalId)

        // 查找对应的 TerminalContent
        guard let node = workspace.nodes.first(where: {
            if case .terminal(let tc) = $0.content { return tc.id == terminalId }
            return false
        }), case .terminal(let tc) = node.content else { return }

        // 重新创建终端（RoleInjector 已在 applyRole 中写入文件）
        _ = TerminalManager.shared.createTerminal(
            id: terminalId,
            command: tc.command,
            workingDirectory: workingDirectory,
            workspaceId: workspace.id,
            roleName: role.name,
            displayName: tc.name
        )
    }

    /// 重启终端在原始工作目录（取消角色后）
    private func restartTerminalInOriginalDir(terminalId: UUID, workingDirectory: String) {
        TerminalManager.shared.removeTerminal(id: terminalId)

        guard let node = workspace.nodes.first(where: {
            if case .terminal(let tc) = $0.content { return tc.id == terminalId }
            return false
        }), case .terminal(let tc) = node.content else { return }

        let dir = workingDirectory.isEmpty ? workspace.workingDirectory : workingDirectory

        _ = TerminalManager.shared.createTerminal(
            id: terminalId,
            command: tc.command,
            workingDirectory: dir,
            workspaceId: workspace.id,
            roleName: nil,
            displayName: tc.name
        )
    }

    /// 获取当前选中节点的内容类型（单选时）
    private var selectedNodeContentType: String? {
        guard selectedNodeIds.count == 1,
              let firstId = selectedNodeIds.first,
              let node = workspace.nodes.first(where: { $0.id == firstId }) else { return nil }
        return contentTypeName(node.content)
    }

    /// FileTree 节点：在访达中显示
    private func revealFileTreeInFinder() {
        guard let firstId = selectedNodeIds.first,
              let node = workspace.nodes.first(where: { $0.id == firstId }),
              case .fileTree(let fc) = node.content else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fc.rootPath)
    }

    /// FileTree 节点：更改根目录
    private func changeFileTreeRoot() {
        guard let firstId = selectedNodeIds.first,
              let idx = workspace.nodes.firstIndex(where: { $0.id == firstId }),
              case .fileTree(let fc) = workspace.nodes[idx].content else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: fc.rootPath)
        panel.prompt = "panel.select_directory".localized
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let newPath = url.path

        // 更新数据模型
        var content = fc
        content.rootPath = newPath
        content.name = url.lastPathComponent
        let newContent = NodeContent.fileTree(content)
        workspace.nodes[idx].content = newContent
        NotificationCenter.default.post(
            name: .canvasNodeContentChanged,
            object: nil,
            userInfo: ["nodeId": firstId, "content": newContent]
        )

        // 通知 CanvasNodeRenderer 刷新视图（通过 save + reload）
        Task { try? await workspace.save() }

        // 发送通知让 renderer 更新文件树视图
        NotificationCenter.default.post(
            name: .fileTreeRootChanged,
            object: nil,
            userInfo: ["nodeId": firstId, "newPath": newPath]
        )
    }
}

// MARK: - 节点类型辅助

private func contentTypeName(_ content: NodeContent) -> String {
    switch content {
    case .terminal:  return "terminal"
    case .stickyNote: return "stickyNote"
    case .portal:    return "portal"
    case .fileTree:  return "fileTree"
    case .text:      return "text"
    case .drawing:   return "drawing"
    }
}

// MARK: - 空画布占位

struct EmptyCanvasPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.dashed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("onboarding.from_here")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("workspace.sidebar.create_hint")
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

// MARK: - Conditional Safe Area

/// 根据条件决定是否忽略顶部安全区域。
/// 非全屏时忽略（工具栏延伸到标题栏）；全屏时不忽略（工具栏在可视区域内正常显示）。
private struct ConditionalIgnoreSafeAreaTop: ViewModifier {
    let ignore: Bool

    func body(content: Content) -> some View {
        if ignore {
            content.ignoresSafeArea(.container, edges: .top)
        } else {
            content
        }
    }
}
