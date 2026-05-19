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
            Section("agent.section.presets") {
                ForEach(appState.preferences.agentPresets) { preset in
                    AgentPresetRow(preset: preset, onToggle: { togglePreset(preset) })
                        .contextMenu {
                            if !preset.isBuiltIn {
                                Button("button.delete", role: .destructive) { deletePreset(preset) }
                            }
                        }
                }
                Button("button.add_custom_preset") { showAddPreset = true }
            }

            // MARK: - 角色管理
            Section {
                if appState.preferences.rolePresets.isEmpty {
                    Text("role.no_roles")
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
                Button("button.add_role") { showAddRole = true }
            } header: {
                Text("role.section")
            } footer: {
                Text("agent.role.footer")
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
            Button("button.edit") { onEdit() }.buttonStyle(.bordered).controlSize(.small)
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
                Text("agent.new_preset").font(.headline)
                Spacer()
                Button("button.cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("button.create") { create() }
                    .disabled(name.isEmpty || command.isEmpty)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }.padding()
            Divider()
            Form {
                TextField("agent.name", text: $name)
                TextField("terminal.command", text: $command)
                    .help(String(localized: "agent.command.help"))
                Picker("agent.type", selection: $agentType) {
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
                Text(role == nil ? "role.new" : "role.edit").font(.headline)
                Spacer()
                Button("button.cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("button.save") { save() }
                    .disabled(name.isEmpty || prompt.isEmpty)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }.padding()
            Divider()
            Form {
                TextField("role.name", text: $name)
                    .help(String(localized: "role.name_placeholder.help"))
                TextEditor(text: $prompt)
                    .frame(height: 100)
                    .font(.system(.body, design: .monospaced))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                Section("agent.color") {
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
                Section("agent.icon") {
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
