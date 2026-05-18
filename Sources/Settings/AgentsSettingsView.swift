import SwiftUI

struct AgentsSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showAddPreset = false
    @State private var showAddRole = false
    @State private var roleToEdit: RolePreset?

    var body: some View {
        @Bindable var state = appState
        Form {
            // MARK: - Agent 预设
            Section("Agent 预设") {
                ForEach(appState.preferences.agentPresets) { preset in
                    AgentPresetRow(preset: preset, onToggle: { togglePreset(preset) })
                        .contextMenu {
                            if !preset.isBuiltIn {
                                Button("删除", role: .destructive) { deletePreset(preset) }
                            }
                        }
                }
                Button("添加自定义预设…") { showAddPreset = true }
            }

            // MARK: - 角色管理
            Section {
                if appState.preferences.rolePresets.isEmpty {
                    Text("暂无角色，点击下方按钮创建")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(appState.preferences.rolePresets) { role in
                        RoleRow(role: role) {
                            roleToEdit = role
                        } onDelete: {
                            deleteRole(role)
                        }
                    }
                }
                Button("新建角色…") { showAddRole = true }
            } header: {
                Text("角色 (Roles)")
            } footer: {
                Text("角色为终端提供初始指令。Maestro 招募子 Agent 时可指定角色。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440)
        .sheet(isPresented: $showAddPreset) {
            AddAgentPresetSheet { newPreset in
                appState.preferences.agentPresets.append(newPreset)
                save()
            }
        }
        .sheet(isPresented: $showAddRole) {
            RoleEditSheet(role: nil) { newRole in
                appState.preferences.rolePresets.append(newRole)
                save()
            }
        }
        .sheet(item: $roleToEdit) { role in
            RoleEditSheet(role: role) { updated in
                if let idx = appState.preferences.rolePresets.firstIndex(where: { $0.id == updated.id }) {
                    appState.preferences.rolePresets[idx] = updated
                    // 更新已写入的角色文件
                    RoleInjector.shared.prepareRoleDirectory(
                        roleId: updated.id,
                        rolePrompt: updated.prompt,
                        workingDirectory: ""
                    )
                }
                save()
            }
        }
    }

    private func togglePreset(_ preset: AgentPreset) {
        guard let idx = appState.preferences.agentPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        appState.preferences.agentPresets[idx].isActive.toggle()
        save()
    }

    private func deletePreset(_ preset: AgentPreset) {
        appState.preferences.agentPresets.removeAll { $0.id == preset.id }
        save()
    }

    private func deleteRole(_ role: RolePreset) {
        appState.preferences.rolePresets.removeAll { $0.id == role.id }
        RoleInjector.shared.removeRoleDirectory(roleId: role.id)
        save()
    }

    private func save() {
        try? PersistenceManager.shared.savePreferences(appState.preferences)
    }
}

// MARK: - Agent 预设行

struct AgentPresetRow: View {
    let preset: AgentPreset
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: preset.color) ?? .accentColor)
                .frame(width: 10, height: 10)
            Image(systemName: preset.icon)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name).font(.body)
                Text(preset.command.isEmpty ? "shell" : preset.command)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onToggle) {
                Toggle("", isOn: .constant(preset.isActive))
                    .labelsHidden()
                    .allowsHitTesting(false)
            }
            .buttonStyle(.plain)
        }
        .opacity(preset.isActive ? 1.0 : 0.5)
    }
}

// MARK: - 角色行

struct RoleRow: View {
    let role: RolePreset
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: role.color) ?? .blue)
                .frame(width: 10, height: 10)
            Image(systemName: role.icon)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(role.name).font(.body)
                Text(role.prompt.prefix(60) + (role.prompt.count > 60 ? "…" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("编辑") { onEdit() }.buttonStyle(.bordered).controlSize(.small)
            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "trash")
            }.buttonStyle(.plain)
        }
    }
}

// MARK: - 新建 Agent 预设 Sheet

struct AddAgentPresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (AgentPreset) -> Void

    @State private var name = ""
    @State private var command = ""
    @State private var icon = "terminal"
    @State private var agentType = "generic_shell"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("新建 Agent 预设").font(.headline)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Button("创建") { create() }
                    .disabled(name.isEmpty || command.isEmpty)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }.padding()
            Divider()
            Form {
                TextField("名称", text: $name)
                TextField("命令", text: $command)
                    .help("Agent 启动命令（如 claude、codex、gemini）")
                Picker("类型", selection: $agentType) {
                    Text("Claude Code").tag("claude_code")
                    Text("Codex").tag("codex")
                    Text("Gemini CLI").tag("gemini_cli")
                    Text("OpenCode").tag("open_code")
                    Text("Shell").tag("generic_shell")
                }
            }
            .formStyle(.grouped).padding()
        }
        .frame(width: 380, height: 280)
    }

    private func create() {
        let preset = AgentPreset(
            id: UUID(), name: name, command: command,
            icon: "terminal", agentType: agentType,
            color: "#007AFF", isActive: true, isBuiltIn: false
        )
        onSave(preset)
        dismiss()
    }
}

// MARK: - 角色编辑 Sheet

struct RoleEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let role: RolePreset?
    let onSave: (RolePreset) -> Void

    @State private var name: String
    @State private var prompt: String
    @State private var color: String
    @State private var icon: String

    private let colorOptions = ["#007AFF", "#34C759", "#FF9500", "#FF3B30", "#AF52DE", "#5856D6"]
    private let iconOptions  = ["person.fill", "wrench.fill", "magnifyingglass", "pencil", "doc.text.fill", "shield.fill", "hammer.fill", "lightbulb.fill"]

    init(role: RolePreset?, onSave: @escaping (RolePreset) -> Void) {
        self.role = role
        self.onSave = onSave
        _name   = State(initialValue: role?.name ?? "")
        _prompt = State(initialValue: role?.prompt ?? "")
        _color  = State(initialValue: role?.color ?? "#007AFF")
        _icon   = State(initialValue: role?.icon ?? "person.fill")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(role == nil ? "新建角色" : "编辑角色").font(.headline)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Button("保存") { save() }
                    .disabled(name.isEmpty || prompt.isEmpty)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }.padding()
            Divider()
            Form {
                TextField("角色名称", text: $name)
                    .help("例如：Leader、Coder、Reviewer、Tester")
                TextEditor(text: $prompt)
                    .frame(height: 100)
                    .font(.system(.body, design: .monospaced))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                Section("颜色") {
                    HStack {
                        ForEach(colorOptions, id: \.self) { c in
                            Button { color = c } label: {
                                Circle()
                                    .fill(Color(hex: c) ?? .blue)
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().stroke(Color.white, lineWidth: color == c ? 2 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("图标") {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 8), spacing: 6) {
                        ForEach(iconOptions, id: \.self) { i in
                            Button { icon = i } label: {
                                Image(systemName: i)
                                    .frame(width: 28, height: 28)
                                    .background(icon == i ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped).padding()
        }
        .frame(width: 440, height: 460)
    }

    private func save() {
        let updated = RolePreset(
            id: role?.id ?? UUID(),
            name: name, prompt: prompt,
            color: color, icon: icon
        )
        onSave(updated)
        dismiss()
    }
}
