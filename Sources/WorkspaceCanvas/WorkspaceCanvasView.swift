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
    @AppStorage("lastSelectedDrawingSubtool") private var activeShapeSubtool: String = "rect"
    @State private var textNodeEditingId: UUID? = nil
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
        .onReceive(NotificationCenter.default.publisher(for: .strokeNodeDrawn)) { notif in
            guard let nodeType = notif.userInfo?["nodeType"] as? String,
                  let startPoint = notif.userInfo?["startPoint"] as? CGPoint,
                  let endPoint = notif.userInfo?["endPoint"] as? CGPoint,
                  let frame = notif.userInfo?["frame"] as? CGRect else { return }
            let strokeType: StrokeType = nodeType == "stroke_arrow" ? .arrow : .line
            createStrokeAtFrame(frame, strokeType: strokeType,
                                startCanvas: startPoint, endCanvas: endPoint)
            activeDrawingTool = nil
        }
    }

    /// 当前是否全屏
    private var isFullScreen: Bool { WindowStateObserver.shared.isFullScreen }

    /// 顶部工具栏覆盖层
    @ViewBuilder
    private var toolbarOverlay: some View {
        VStack(spacing: 0) {
            // 浮动工具栏（距窗口顶部 8px）
            CanvasToolbar(workspace: workspace, isConnecting: $isConnecting, activeDrawingTool: $activeDrawingTool, activeShapeSubtool: $activeShapeSubtool)
                .padding(.top, 8)

            // 二级操作工具栏（选中节点时显示）
            // 与一级工具栏间距加大
            Spacer().frame(height: 12)

            // 绘制工具激活时隐藏节点工具栏（二级工具栏唯一实例）
            if activeDrawingTool == nil && !selectedNodeIds.isEmpty && selectedNodeIds.contains(where: { id in
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
                        fontSize: noteFontSize(nodeId: noteId),
                        currentColor: noteCurrentColor(nodeId: noteId),
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
                } else if selectedNodeContentType == "text",
                          let textId = selectedNodeIds.first {
                    TextContextToolbar(
                        nodeId: textId,
                        fontSize: textFontSize(nodeId: textId),
                        fontWeight: textFontWeight(nodeId: textId),
                        fontFamily: textFontFamily(nodeId: textId),
                        currentColor: textCurrentColor(nodeId: textId),
                        onFontSize: { size in setTextFontSize(nodeId: textId, size: size) },
                        onFontWeight: { weight in setTextFontWeight(nodeId: textId, weight: weight) },
                        onFontFamily: { family in setTextFontFamily(nodeId: textId, family: family) },
                        onColor: { color in setTextColor(nodeId: textId, color: color) },
                        onDelete: { deleteSelectedNodes() }
                    )
                    .fixedSize()
                    .padding(.bottom, 36)
                    .contentShape(Rectangle())
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut(duration: 0.15), value: selectedNodeIds)
                } else if selectedNodeContentType == "shape",
                          let shapeId = selectedNodeIds.first,
                          let sc = shapeContent(nodeId: shapeId) {
                    ShapeContextToolbar(
                        nodeId: shapeId,
                        content: sc,
                        onContentChange: { newContent in setShapeContent(nodeId: shapeId, content: newContent) },
                        onDelete: { deleteSelectedNodes() }
                    )
                    .fixedSize()
                    .padding(.bottom, 36)
                    .contentShape(Rectangle())
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut(duration: 0.15), value: selectedNodeIds)
                } else if selectedNodeContentType == "stroke",
                          let strokeId = selectedNodeIds.first,
                          let sc = strokeContent(nodeId: strokeId) {
                    StrokeContextToolbar(
                        nodeId: strokeId,
                        content: sc,
                        onContentChange: { newContent in setStrokeContent(nodeId: strokeId, content: newContent) },
                        onDelete: { deleteSelectedNodes() }
                    )
                    .fixedSize()
                    .padding(.bottom, 36)
                    .contentShape(Rectangle())
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut(duration: 0.15), value: selectedNodeIds)
                } else if selectedNodeContentType == "freehand",
                          let freehandId = selectedNodeIds.first,
                          let fc = freehandContent(nodeId: freehandId) {
                    FreehandContextToolbar(
                        nodeId: freehandId,
                        content: fc,
                        onContentChange: { newContent in setFreehandContent(nodeId: freehandId, content: newContent) },
                        onDelete: { deleteSelectedNodes() }
                    )
                    .fixedSize()
                    .padding(.bottom, 36)
                    .contentShape(Rectangle())
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut(duration: 0.15), value: selectedNodeIds)
                } else if selectedNodeIds.count > 1 {
                    HStack(spacing: 2) {
                        ContextToolbarButton(
                            icon: "trash",
                            tooltip: "tooltip.node.delete".localized,
                            action: { deleteSelectedNodes() }
                        )
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color(white: 0.9), lineWidth: 0.5)
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

    /// 构建 CanvasViewportRepresentable（单独提取以帮助编译器推断类型）
    private var canvasViewportRepresentable: CanvasViewportRepresentable {
        CanvasViewportRepresentable(
            canvasOrigin: $canvasOrigin,
            zoom: $zoom,
            backgroundMode: backgroundMode,
            workspace: workspace,
            isConnecting: isConnecting,
            isDrawingMode: activeDrawingTool != nil,
            drawingNodeType: activeDrawingTool == "shape" ? activeShapeSubtool : (activeDrawingTool ?? "terminal"),
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
            onConnectionCreated: handleConnectionCreated(idA:idB:),
            onNodeDrawn: { nodeType, canvasRect in
                handleNodeDrawn(nodeType: nodeType, frame: canvasRect)
            },
            onFreehandDrawn: { (nodeType: String, normalizedPoints: [CGPoint], boundingFrame: CGRect) in
                handleFreehandDrawn(nodeType: nodeType, points: normalizedPoints, frame: boundingFrame)
            },
            onSelectionChanged: { ids, frame in
                selectedNodeIds = ids
                selectedNodeScreenFrame = frame
                if let editingId = textNodeEditingId, !ids.contains(editingId) {
                    textNodeEditingId = nil
                }
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
    }

    @ViewBuilder
    private var canvasBody: some View {
        ZStack {
            canvasViewportRepresentable
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
        .sheet(isPresented: $showTerminalSheetForDrawing, onDismiss: { activeDrawingTool = nil }) {
            NewTerminalSheet(
                initialPresets: appState.preferences.agentPresets.filter { $0.isActive },
                initialRoles: appState.preferences.rolePresets,
                defaultWorkingDirectory: workspace.workingDirectory
            ) { preset, role, isManager, workDir in
                createTerminalAtFrame(showTerminalDrawnFrame, preset: preset, role: role, isManager: isManager, workingDirectory: workDir)
            }
            .environment(\.locale, LocalizationManager.shared.locale)
        }
        .sheet(isPresented: $showPortalSheetForDrawing, onDismiss: { activeDrawingTool = nil }) {
            NewPortalSheet { name, url in
                createPortalAtFrame(showPortalDrawnFrame, name: name, url: url)
            }
            .environment(\.locale, LocalizationManager.shared.locale)
        }
        .onReceive(NotificationCenter.default.publisher(for: .textNodeDidChange)) { notif in
            guard let nodeId = notif.userInfo?["nodeId"] as? UUID,
                  let text   = notif.userInfo?["text"] as? String,
                  let idx    = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
                  case .text(var tc) = workspace.nodes[idx].content else { return }
            tc.text = text
            workspace.nodes[idx].content = .text(tc)
            let newSize = measuredTextNodeSize(tc)
            let newFrame = CGRect(origin: workspace.nodes[idx].frame.origin, size: newSize)
            workspace.updateNodeFrame(id: nodeId, frame: newFrame)
            NotificationCenter.default.post(
                name: .canvasNodeContentChanged,
                object: nil,
                userInfo: ["nodeId": nodeId, "content": workspace.nodes[idx].content, "frame": newFrame]
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .textNodeDidEndEditing)) { notif in
            guard let nodeId = notif.userInfo?["nodeId"] as? UUID,
                  let text   = notif.userInfo?["text"] as? String else { return }
            if let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
               case .text(var tc) = workspace.nodes[idx].content {
                tc.text = text
                workspace.nodes[idx].content = .text(tc)
                if !text.isEmpty {
                    let newSize = measuredTextNodeSize(tc)
                    let newFrame = CGRect(origin: workspace.nodes[idx].frame.origin, size: newSize)
                    workspace.updateNodeFrame(id: nodeId, frame: newFrame)
                    NotificationCenter.default.post(
                        name: .canvasNodeContentChanged,
                        object: nil,
                        userInfo: ["nodeId": nodeId, "content": workspace.nodes[idx].content, "frame": newFrame]
                    )
                } else {
                    NotificationCenter.default.post(
                        name: .canvasNodeContentChanged,
                        object: nil,
                        userInfo: ["nodeId": nodeId, "content": workspace.nodes[idx].content]
                    )
                }
                Task { try? await workspace.save() }
            }
            textNodeEditingId = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .textNodeShouldBeginEditing)) { notif in
            guard let nodeId = notif.userInfo?["nodeId"] as? UUID else { return }
            selectedNodeIds = [nodeId]
            textNodeEditingId = nodeId
        }
        .onReceive(NotificationCenter.default.publisher(for: .shapeNodeTextDidEndEditing)) { notif in
            guard let id = notif.userInfo?["nodeId"] as? UUID,
                  let text = notif.userInfo?["text"] as? String,
                  var sc = shapeContent(nodeId: id) else { return }
            sc.text = text
            setShapeContent(nodeId: id, content: sc)
        }
        .onReceive(NotificationCenter.default.publisher(for: .shapeNodeRotationChanged)) { notif in
            guard let id = notif.userInfo?["nodeId"] as? UUID,
                  let rotation = notif.userInfo?["rotation"] as? CGFloat,
                  let idx = workspace.nodes.firstIndex(where: { $0.id == id }),
                  case .shape(var sc) = workspace.nodes[idx].content else { return }
            sc.rotation = rotation
            let newContent = NodeContent.shape(sc)
            workspace.nodes[idx].content = newContent
            NotificationCenter.default.post(
                name: .canvasNodeContentChanged,
                object: nil,
                userInfo: ["nodeId": id, "content": newContent]
            )
            // Save deferred to rotation end
        }
        .onReceive(NotificationCenter.default.publisher(for: .shapeNodeRotationDidEnd)) { notif in
            guard let _ = notif.userInfo?["nodeId"] as? UUID else { return }
            Task { try? await workspace.save() }
        }
        .strokePointDragHandler(workspace: workspace)
        .autosave(workspace: workspace)
        .environment(\.textNodeEditingId, textNodeEditingId)
    }

    // MARK: - 拖拽绘制创建节点

    private func handleNodeDrawn(nodeType: String, frame: CGRect) {
        switch nodeType {
        case "terminal":
            showTerminalDrawnFrame = frame
            showTerminalSheetForDrawing = true
        case "stickyNote":
            createNoteAtFrame(frame)
            activeDrawingTool = nil
        case "portal":
            showPortalDrawnFrame = frame
            showPortalSheetForDrawing = true
        case "fileTree":
            createFileTreeAtFrame(frame)
            activeDrawingTool = nil
        case "text":
            createTextAtFrame(frame)
            activeDrawingTool = nil
        case "rect":
            createShapeAtFrame(frame, shapeType: .rect)
            activeDrawingTool = nil
        case "ellipse":
            createShapeAtFrame(frame, shapeType: .ellipse)
            activeDrawingTool = nil
        case "diamond":
            createShapeAtFrame(frame, shapeType: .diamond)
            activeDrawingTool = nil
        case "shape":
            createShapeAtFrame(frame, shapeType: .rect)
            activeDrawingTool = nil
        default:
            break
        }
    }

    private func handleConnectionCreated(idA: UUID, idB: UUID) {
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
    }

    private func handleFreehandDrawn(nodeType: String, points: [CGPoint], frame: CGRect) {
        let freehandType: FreehandType = nodeType == "freehand_highlighter" ? .highlighter : .pen
        createFreehandFromPoints(points, boundingFrame: frame, freehandType: freehandType)
        activeDrawingTool = nil
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
    @State private var showTerminalDrawnFrame: CGRect = .zero
    @State private var showTerminalSheetForDrawing = false
    @State private var showPortalDrawnFrame: CGRect = .zero
    @State private var showPortalSheetForDrawing = false
    // MARK: - Maestro Recruit 处理
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
    case .shape:     return "shape"
    case .stroke:    return "stroke"
    case .freehand:  return "freehand"
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

// MARK: - Stroke Point Drag Modifier

/// 处理 stroke 控制点拖拽结束时的 workspace 持久化。
/// 独立提取为 ViewModifier，避免 body 链过长导致 Swift 编译器类型推断超时。
private struct StrokePointDragModifier: ViewModifier {
    @Bindable var workspace: WorkspaceManager

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .strokePointDragDidEnd)) { notif in
                guard let id = notif.userInfo?["nodeId"] as? UUID,
                      let nodeContent = notif.userInfo?["content"] as? NodeContent,
                      let idx = workspace.nodes.firstIndex(where: { $0.id == id }) else { return }
                workspace.nodes[idx].content = nodeContent
                if let newFrame = notif.userInfo?["frame"] as? CGRect {
                    workspace.nodes[idx].frame = newFrame
                }
                Task { try? await workspace.save() }
            }
    }
}

private extension View {
    func strokePointDragHandler(workspace: WorkspaceManager) -> some View {
        modifier(StrokePointDragModifier(workspace: workspace))
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
