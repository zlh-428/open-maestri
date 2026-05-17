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
                    isActive: activeDrawingTool == nil && !isConnecting
                ) {
                    activeDrawingTool = nil
                    isConnecting = false
                }
                .help("选择工具")

                // Terminal 工具
                FloatingToolButton(
                    icon: "terminal.fill",
                    isActive: activeDrawingTool == "terminal"
                ) {
                    toggleDrawingTool("terminal")
                }
                .help("终端")

                // Note 工具
                FloatingToolButton(
                    icon: "note.text",
                    isActive: activeDrawingTool == "stickyNote"
                ) {
                    toggleDrawingTool("stickyNote")
                }
                .help("笔记")

                // Portal 工具
                FloatingToolButton(
                    icon: "globe",
                    isActive: activeDrawingTool == "portal"
                ) {
                    toggleDrawingTool("portal")
                }
                .help("浏览器")

                // FileTree 工具
                FloatingToolButton(
                    icon: "folder.fill",
                    isActive: activeDrawingTool == "fileTree"
                ) {
                    toggleDrawingTool("fileTree")
                }
                .help("文件树")

                // 分割线
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 4)

                // 连线工具（L）
                FloatingToolButton(
                    icon: "link",
                    isActive: isConnecting
                ) {
                    isConnecting.toggle()
                    activeDrawingTool = nil
                }
                .help("创建连接（L）")

                // 格式工具（预留）
                FloatingToolButton(
                    icon: "textformat",
                    isActive: false
                ) {
                    // 预留
                }
                .help("格式")
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
    var isActive: Bool = false
    let action: () -> Void

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
    }
}

// MARK: - 新建 Terminal Sheet

struct NewTerminalSheet: View {
    let initialPresets: [AgentPreset]
    let initialRoles: [RolePreset]
    let defaultWorkingDirectory: String
    let onConfirm: (AgentPreset, RolePreset?, Bool, String) -> Void  // preset, role, isManager, workingDirectory
    @Environment(\.dismiss) private var dismiss

    // 选中状态
    @State private var selectedIdx: Int = 0
    @State private var selectedRoleIdx: Int? = nil

    // Tab 切换: 0=详细信息, 1=外观, 2=角色
    @State private var selectedTab: Int = 0

    // 表单字段
    @State private var terminalName: String = ""
    @State private var command: String = ""
    @State private var monitorActivity: Bool = true
    @State private var isMaestroMode: Bool = false
    @State private var workingDirectory: String = ""

    // 焦点控制
    enum Field: Hashable { case name, command }
    @FocusState private var focusedField: Field?

    var body: some View {
        let ps = initialPresets
        let rs = initialRoles

        VStack(spacing: 0) {
            // MARK: 标题
            Text("新建终端")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 16)
                .padding(.bottom, 12)

            // MARK: 快速开始 - Agent 图标行
            VStack(alignment: .leading, spacing: 8) {
                Text("快速开始")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    ForEach(Array(ps.enumerated()), id: \.offset) { idx, preset in
                        AgentIconButton(
                            preset: preset,
                            isSelected: selectedIdx == idx
                        ) {
                            selectedIdx = idx
                            // 切换 agent 时更新名称和命令
                            terminalName = preset.name
                            command = preset.command
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 14)

            // MARK: 分段 Tab 控件
            Picker("", selection: $selectedTab) {
                Text("详细信息").tag(0)
                Text("外观").tag(1)
                Text("角色").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            // MARK: Tab 内容（条件渲染，确保每次只渲染当前 Tab，避免 TextField 焦点互相干扰）
            Group {
                if selectedTab == 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        detailsTabContent
                    }
                } else if selectedTab == 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        appearanceTabContent
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        roleTabContent(roles: rs)
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Spacer(minLength: 8)

            // MARK: 底部按钮
            HStack(spacing: 12) {
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )

                Button("创建") {
                    confirmCreation(presets: ps, roles: rs)
                }
                .buttonStyle(.borderedProminent)
                .disabled(ps.isEmpty)
            }
            .padding(.bottom, 16)
        }
        .frame(width: 400, height: 480)
        .task { activateFirstTextField() }
        .onAppear {
            if !initialPresets.isEmpty {
                terminalName = initialPresets[selectedIdx].name
                command = initialPresets[selectedIdx].command
            }
            workingDirectory = defaultWorkingDirectory
        }
    }

    // MARK: - 确认创建

    private func confirmCreation(presets: [AgentPreset], roles: [RolePreset]) {
        guard selectedIdx < presets.count else { return }
        var finalPreset = presets[selectedIdx]
        if !terminalName.isEmpty {
            finalPreset.name = terminalName
        }
        if !command.isEmpty {
            finalPreset.command = command
        }
        let role: RolePreset? = selectedRoleIdx.map { roles[$0] }
        let dir = workingDirectory.isEmpty ? defaultWorkingDirectory : workingDirectory
        onConfirm(finalPreset, role, isMaestroMode, dir)
        dismiss()
    }

    // MARK: - 详细信息 Tab

    @ViewBuilder
    private var detailsTabContent: some View {
        // 终端名称
        VStack(alignment: .leading, spacing: 4) {
            Text("名称")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("终端名称", text: $terminalName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($focusedField, equals: .name)
        }

        // 命令
        VStack(alignment: .leading, spacing: 4) {
            Text("命令")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("例如: claude, codex, gemini", text: $command)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($focusedField, equals: .command)
        }

        // 复选框
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $monitorActivity) {
                HStack(spacing: 4) {
                    Image(systemName: "eye")
                        .font(.system(size: 11))
                    Text("监控活动")
                        .font(.system(size: 12))
                }
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $isMaestroMode) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(.purple)
                    Text("Maestro")
                        .font(.system(size: 12))
                }
            }
            .toggleStyle(.checkbox)
            .help("Maestro 终端可通过 omaestri recruit 命令招募子 Agent")
        }
        .padding(.top, 4)

        // 工作目录（只读显示 + 选择按钮）
        VStack(alignment: .leading, spacing: 4) {
            Text("工作目录")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(workingDirectory.isEmpty ? "未选择" : abbreviatePath(workingDirectory))
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )

                Button("选择…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.directoryURL = URL(fileURLWithPath: workingDirectory)
                    if panel.runModal() == .OK, let url = panel.url {
                        workingDirectory = url.path
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.top, 4)
    }

    /// 缩短路径显示（将用户目录替换为 ~）
    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - 外观 Tab

    @ViewBuilder
    private var appearanceTabContent: some View {
        let ps = initialPresets
        if selectedIdx < ps.count {
            let preset = ps[selectedIdx]
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: preset.color) ?? .blue)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: preset.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name)
                            .font(.system(size: 13, weight: .medium))
                        Text(preset.agentType)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("外观自定义功能即将推出")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - 角色 Tab

    @ViewBuilder
    private func roleTabContent(roles: [RolePreset]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 无角色选项
            Button { selectedRoleIdx = nil } label: {
                RoleOptionRow(name: "无角色", icon: "xmark.circle", color: "#8E8E93",
                        isSelected: selectedRoleIdx == nil)
            }
            .buttonStyle(.plain)

            if roles.isEmpty {
                Text("暂无自定义角色，可在设置中添加")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            } else {
                ForEach(Array(roles.enumerated()), id: \.offset) { idx, role in
                    Button { selectedRoleIdx = idx } label: {
                        RoleOptionRow(name: role.name, icon: role.icon, color: role.color,
                                isSelected: selectedRoleIdx == idx)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Agent 图标按钮

private struct AgentIconButton: View {
    let preset: AgentPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected
                              ? (Color(hex: preset.color) ?? .blue).opacity(0.15)
                              : Color(nsColor: .controlBackgroundColor))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected
                                        ? (Color(hex: preset.color) ?? .blue)
                                        : Color.secondary.opacity(0.2),
                                        lineWidth: isSelected ? 1.5 : 0.5)
                        )

                    Image(systemName: preset.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: preset.color) ?? .blue)
                }

                Text(preset.name)
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 角色选择行

private struct RoleOptionRow: View {
    let name: String
    let icon: String
    let color: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: color) ?? .gray)
                .frame(width: 8, height: 8)
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 18)
            Text(name)
                .font(.system(size: 12))
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - 新建 Portal Sheet

struct NewPortalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: (String) -> Void
    @State private var url = "https://"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("新建 Portal").font(.headline)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Button("创建") { onConfirm(url); dismiss() }
                    .disabled(url.isEmpty)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }.padding()
            Divider()
            Form {
                TextField("URL", text: $url)
                    .textFieldStyle(.roundedBorder)
            }.formStyle(.grouped).padding()
        }
        .frame(width: 360, height: 160)
    }
}

// MARK: - 新建 FileTree Sheet

struct NewFileTreeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let defaultPath: String
    let onConfirm: (String) -> Void
    @State private var path: String

    init(defaultPath: String, onConfirm: @escaping (String) -> Void) {
        self.defaultPath = defaultPath
        self.onConfirm = onConfirm
        _path = State(initialValue: defaultPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("新建文件树").font(.headline)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Button("创建") { onConfirm(path); dismiss() }
                    .disabled(path.isEmpty)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }.padding()
            Divider()
            Form {
                HStack {
                    TextField("目录路径", text: $path).textFieldStyle(.roundedBorder)
                    Button("选择…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url {
                            path = url.path
                        }
                    }
                }
            }.formStyle(.grouped).padding()
        }
        .frame(width: 400, height: 160)
    }
}



// MARK: - Color(hex:)

private extension Color {
    init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8) & 0xFF) / 255,
            blue: Double(val & 0xFF) / 255
        )
    }
}
