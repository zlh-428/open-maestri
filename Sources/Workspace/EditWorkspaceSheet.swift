import SwiftUI

/// 编辑工作区 Sheet（FR1 扩展：名称/目录/图标/Agent 指令/同步配置）
struct EditWorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: WorkspaceEntry
    let onSave: (WorkspaceEntry) -> Void

    @State private var name: String
    @State private var workingDirectory: String
    @State private var selectedIcon: String
    @State private var syncConfigFiles: Bool

    // Agent 指令 Tab 状态
    @State private var claudeMdContent: String = ""
    @State private var agentsMdContent: String = ""
    @State private var selectedTab: EditTab = .general
    @State private var agentFilesDirty = false

    enum EditTab { case general, agentInstructions }

    private let iconOptions = [
        "folder", "folder.fill", "terminal.fill", "cpu",
        "brain", "desktopcomputer", "network", "server.rack",
        "doc.text", "swift", "wrench", "gear"
    ]

    init(entry: WorkspaceEntry, onSave: @escaping (WorkspaceEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _name = State(initialValue: entry.name)
        _workingDirectory = State(initialValue: entry.workingDirectory)
        _selectedIcon = State(initialValue: entry.icon)
        _syncConfigFiles = State(initialValue: false)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("编辑工作区")
                    .font(.headline)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Button("保存") { save() }
                    .keyboardShortcut(.return)
                    .disabled(name.isEmpty || workingDirectory.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Tab 选择器
            Picker("", selection: $selectedTab) {
                Text("常规").tag(EditTab.general)
                Text("Agent 指令").tag(EditTab.agentInstructions)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Tab 内容
            switch selectedTab {
            case .general:
                generalTab
            case .agentInstructions:
                agentInstructionsTab
            }
        }
        .frame(width: 560, height: 520)
        .onAppear { loadAgentFiles() }
        .onChange(of: workingDirectory) { _, _ in loadAgentFiles() }
    }

    // MARK: - 常规 Tab

    private var generalTab: some View {
        Form {
            Section("基本信息") {
                TextField("工作区名称", text: $name).textFieldStyle(.roundedBorder)
                HStack {
                    TextField("工作目录", text: $workingDirectory).textFieldStyle(.roundedBorder)
                    Button("选择…") { pickDirectory() }
                }
            }

            Section("图标") {
                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 8), spacing: 8) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Button { selectedIcon = icon } label: {
                            Image(systemName: icon)
                                .frame(width: 32, height: 32)
                                .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
    }

    // MARK: - Agent 指令 Tab（内联编辑 CLAUDE.md / AGENTS.md）

    private var agentInstructionsTab: some View {
        VStack(spacing: 0) {
            // 同步开关
            HStack {
                Toggle("同步 CLAUDE.md ↔ AGENTS.md", isOn: $syncConfigFiles)
                    .help("修改任意一个文件时，自动同步到另一个文件")
                    .onChange(of: syncConfigFiles) { _, sync in
                        if sync { agentsMdContent = claudeMdContent }
                    }
                Spacer()
                if agentFilesDirty {
                    Button("保存文件") { saveAgentFiles() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // 编辑区：同步时单栏，非同步时双栏
            if syncConfigFiles {
                VStack(alignment: .leading, spacing: 4) {
                    Label("CLAUDE.md / AGENTS.md（同步）", systemImage: "doc.text")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    TextEditor(text: Binding(
                        get: { claudeMdContent },
                        set: { v in
                            claudeMdContent = v
                            agentsMdContent = v
                            agentFilesDirty = true
                        }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    // CLAUDE.md
                    VStack(alignment: .leading, spacing: 4) {
                        Label("CLAUDE.md", systemImage: "doc.text")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        TextEditor(text: Binding(
                            get: { claudeMdContent },
                            set: { v in claudeMdContent = v; agentFilesDirty = true }
                        ))
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 4)
                    }
                    Divider()
                    // AGENTS.md
                    VStack(alignment: .leading, spacing: 4) {
                        Label("AGENTS.md", systemImage: "doc.text")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        TextEditor(text: Binding(
                            get: { agentsMdContent },
                            set: { v in agentsMdContent = v; agentFilesDirty = true }
                        ))
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
    }

    // MARK: - 私有方法

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            workingDirectory = url.path
        }
    }

    private func loadAgentFiles() {
        let claudePath = workingDirectory + "/CLAUDE.md"
        let agentsPath = workingDirectory + "/AGENTS.md"
        claudeMdContent = (try? String(contentsOfFile: claudePath, encoding: .utf8)) ?? ""
        agentsMdContent = (try? String(contentsOfFile: agentsPath, encoding: .utf8)) ?? ""
        agentFilesDirty = false
    }

    private func saveAgentFiles() {
        let claudePath = workingDirectory + "/CLAUDE.md"
        let agentsPath = workingDirectory + "/AGENTS.md"
        try? claudeMdContent.write(toFile: claudePath, atomically: true, encoding: .utf8)
        if syncConfigFiles {
            try? claudeMdContent.write(toFile: agentsPath, atomically: true, encoding: .utf8)
        } else {
            try? agentsMdContent.write(toFile: agentsPath, atomically: true, encoding: .utf8)
        }
        agentFilesDirty = false
    }

    private func save() {
        // 保存 Agent 指令文件
        if agentFilesDirty { saveAgentFiles() }
        var updated = entry
        updated.name = name
        updated.workingDirectory = workingDirectory
        updated.icon = selectedIcon
        onSave(updated)
        dismiss()
    }
}
