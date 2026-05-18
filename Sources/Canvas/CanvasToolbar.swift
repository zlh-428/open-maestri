import SwiftUI
import AppKit

/// 画布顶部工具栏
/// 支持新建 Terminal/Note/Portal/FileTree 节点（拖拽绘制模式），以及连线工具
struct CanvasToolbar: View {
    let workspace: WorkspaceManager
    @Binding var isConnecting: Bool
    /// 当前选中的绘制工具（nil = 选择模式，非绘制）
    @Binding var activeDrawingTool: String?
    @Environment(AppState.self) private var appState

    @State private var showTerminalSheet = false
    @State private var showNoteCreated = false
    @State private var showPortalSheet = false
    @State private var showFileTreeSheet = false

    var body: some View {
        // 居中悬浮工具栏（参考 Maestri 产品设计）
        HStack(spacing: 0) {
            Spacer()

            HStack(spacing: 2) {
                // 选择工具（默认）
                FloatingToolButton(
                    icon: "cursorarrow",
                    tooltip: "选择工具",
                    isActive: activeDrawingTool == nil && !isConnecting
                ) {
                    activeDrawingTool = nil
                    isConnecting = false
                }

                // Terminal 工具
                FloatingToolButton(
                    icon: "terminal.fill",
                    tooltip: "终端",
                    isActive: activeDrawingTool == "terminal"
                ) {
                    toggleDrawingTool("terminal")
                }

                // Note 工具
                FloatingToolButton(
                    icon: "note.text",
                    tooltip: "笔记",
                    isActive: activeDrawingTool == "stickyNote"
                ) {
                    toggleDrawingTool("stickyNote")
                }

                // Portal 工具
                FloatingToolButton(
                    icon: "globe",
                    tooltip: "浏览器",
                    isActive: activeDrawingTool == "portal"
                ) {
                    toggleDrawingTool("portal")
                }

                // Text 工具
                FloatingToolButton(
                    icon: "textformat.abc",
                    tooltip: "文本标签",
                    isActive: activeDrawingTool == "text"
                ) {
                    toggleDrawingTool("text")
                }

                // Drawing 工具
                FloatingToolButton(
                    icon: "pencil.tip.crop.circle",
                    tooltip: "手绘",
                    isActive: activeDrawingTool == "drawing"
                ) {
                    toggleDrawingTool("drawing")
                }

                // FileTree 工具
                FloatingToolButton(
                    icon: "folder.fill",
                    tooltip: "文件树",
                    isActive: activeDrawingTool == "fileTree"
                ) {
                    toggleDrawingTool("fileTree")
                }

                // 分割线
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 4)

                // 连线工具（L）
                FloatingToolButton(
                    icon: "link",
                    tooltip: "创建连接（L）",
                    isActive: isConnecting
                ) {
                    isConnecting.toggle()
                    activeDrawingTool = nil
                }

                // 格式工具（预留）
                FloatingToolButton(
                    icon: "textformat",
                    tooltip: "格式",
                    isActive: false
                ) {
                    // 预留
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)

            Spacer()
        }
        .padding(.top, 10)
        .sheet(isPresented: $showTerminalSheet) {
            NewTerminalSheet(
                initialPresets: appState.preferences.agentPresets.filter { $0.isActive },
                initialRoles: appState.preferences.rolePresets,
                defaultWorkingDirectory: workspace.workingDirectory
            ) { preset, role, isManager, workDir in
                createTerminal(preset: preset, role: role, isManager: isManager, workingDirectory: workDir)
            }
        }
        .sheet(isPresented: $showPortalSheet) {
            NewPortalSheet { url in
                createPortal(url: url)
            }
        }
        .sheet(isPresented: $showFileTreeSheet) {
            NewFileTreeSheet(defaultPath: workspace.workingDirectory) { path in
                createFileTree(rootPath: path)
            }
        }
    }

    private func toggleDrawingTool(_ tool: String) {
        if activeDrawingTool == tool {
            activeDrawingTool = nil
        } else {
            activeDrawingTool = tool
            isConnecting = false
        }
    }

    // MARK: - 创建节点

    private func createTerminal(preset: AgentPreset, role: RolePreset?, isManager: Bool = false, workingDirectory: String? = nil) {
        let dir = workingDirectory ?? workspace.workingDirectory
        var tc = TerminalContent(
            name: preset.name,
            agentType: preset.agentType,
            command: preset.command,
            workingDirectory: dir
        )
        tc.isManager = isManager
        let origin = nextNodeOrigin(width: 600, height: 400)
        // 使用 tc.id 作为 CanvasNode.id，确保 node.id == tc.id（避免 removeNode 时失同步）
        let node = CanvasNode(
            id: tc.id,
            frame: CGRect(origin: origin, size: CGSize(width: 600, height: 400)),
            content: .terminal(tc)
        )
        addNode(node)
        let wsId = workspace.id
        Task { @MainActor in
            _ = TerminalManager.shared.createTerminal(
                id: tc.id, workingDirectory: tc.workingDirectory,
                preset: preset, role: role, workspaceId: wsId
            )
        }
    }

    private func createNote() {
        let name = "Note-\(UUID().uuidString.prefix(6))"
        let fileName = "\(name).md"
        let nc = StickyNoteContent(name: name)
        var mutableNC = nc
        mutableNC.fileName = fileName
        let origin = nextNodeOrigin(width: 260, height: 200)
        let node = CanvasNode(
            frame: CGRect(origin: origin, size: CGSize(width: 260, height: 200)),
            content: .stickyNote(mutableNC)
        )
        // 创建文件
        let filePath = PersistenceManager.shared.notesDirURL(workspaceId: workspace.id)
            .appendingPathComponent(fileName).path
        try? FileManager.default.createDirectory(
            atPath: PersistenceManager.shared.notesDirURL(workspaceId: workspace.id).path,
            withIntermediateDirectories: true
        )
        try? "".write(toFile: filePath, atomically: true, encoding: .utf8)
        NoteRegistry.shared.register(name: name, filePath: filePath, nodeId: node.id)
        addNode(node)
    }

    private func createPortal(url: String) {
        let pc = PortalContent(name: "Portal", url: url)
        let origin = nextNodeOrigin(width: 800, height: 600)
        let node = CanvasNode(
            frame: CGRect(origin: origin, size: CGSize(width: 800, height: 600)),
            content: .portal(pc)
        )
        addNode(node)
    }

    private func createFileTree(rootPath: String? = nil) {
        let path = rootPath ?? workspace.workingDirectory
        let fc = FileTreeContent(name: URL(fileURLWithPath: path).lastPathComponent, rootPath: path)
        let origin = nextNodeOrigin(width: 300, height: 500)
        let node = CanvasNode(
            frame: CGRect(origin: origin, size: CGSize(width: 300, height: 500)),
            content: .fileTree(fc)
        )
        addNode(node)
    }

    private func addNode(_ node: CanvasNode) {
        workspace.addNode(node)
        // 立即保存（不等 autosave 延迟）
        Task { try? await workspace.save() }
        // Spotlight 更新
        SpotlightIndexer.shared.indexWorkspaceNodes(
            workspaceId: workspace.id,
            nodes: [node],
            workingDirectory: workspace.workingDirectory
        )
    }

    private func nextNodeOrigin(width: CGFloat, height: CGFloat) -> CGPoint {
        // 基于现有节点数量偏移，避免完全重叠
        let count = CGFloat(workspace.nodes.count)
        let col = Int(count) % 4
        let row = Int(count) / 4
        let baseX = Constants.canvasInitialOrigin.x + 100
        let baseY = Constants.canvasInitialOrigin.y + 100
        let stepX = width + 30
        let stepY = height + 60
        return CGPoint(x: baseX + CGFloat(col) * stepX, y: baseY + CGFloat(row) * stepY)
    }
}

// MARK: - 悬浮工具栏按钮

private struct FloatingToolButton: View {
    let icon: String
    var tooltip: String = ""
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.7))
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .background(
            HoverTrackingView { hovering in
                if hovering {
                    if !isHovered {
                        isHovered = true
                        hoverTask = Task {
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            guard !Task.isCancelled else { return }
                            showTooltip = true
                        }
                    }
                } else {
                    isHovered = false
                    hoverTask?.cancel()
                    hoverTask = nil
                    showTooltip = false
                }
            }
        )
        .overlay(alignment: .bottom) {
            if showTooltip && !tooltip.isEmpty {
                Text(tooltip)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(white: 0.88), lineWidth: 0.5)
                    )
                    .fixedSize()
                    .offset(y: 34)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                    .zIndex(1000)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showTooltip)
    }
}

