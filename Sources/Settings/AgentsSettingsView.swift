import OSLog
import SwiftUI

private let settingsLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "open-maestri", category: "Settings")

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
            .environment(\.locale, LocalizationManager.shared.locale)
        }
        .sheet(isPresented: $showAddRole) {
            RoleEditSheet(role: nil) { newRole in
                appState.preferences.rolePresets.append(newRole)
                save()
            }
            .environment(\.locale, LocalizationManager.shared.locale)
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
            .environment(\.locale, LocalizationManager.shared.locale)
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
        do {
                try PersistenceManager.shared.savePreferences(appState.preferences)
            } catch {
                settingsLogger.error("Failed to save preferences: \(error.localizedDescription)")
            }
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
                    .help("agent.command.help".localized)
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
    @State private var selectedTab: Int = 0

    private let colorOptions = [
        "#007AFF", "#34C759", "#FF9500", "#FF3B30", "#AF52DE", "#5856D6",
        "#FF2D55", "#5AC8FA", "#FFCC00", "#4CD964", "#8E8E93", "#FF6482"
    ]
    private let iconOptions = [
        "person.fill", "wrench.fill", "magnifyingglass", "pencil",
        "doc.text.fill", "shield.fill", "hammer.fill", "lightbulb.fill",
        "brain", "eye.fill", "checkmark.seal.fill", "ant.fill",
        "terminal", "gear", "paintbrush.fill", "scissors",
        "flag.fill", "bolt.fill", "leaf.fill", "star.fill",
        "heart.fill", "hand.raised.fill", "scope", "chart.bar.fill"
    ]

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
            // Header
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

            // Tab 切换
            Picker("", selection: $selectedTab) {
                Text("agent.tab.basic_info").tag(0)
                Text("agent.tab.instructions_preview").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Tab 内容
            if selectedTab == 0 {
                roleBasicInfoTab
            } else {
                roleInstructionPreviewTab
            }
        }
        .frame(width: 500, height: 560)
    }

    // MARK: - 基本信息 Tab

    @ViewBuilder
    private var roleBasicInfoTab: some View {
        Form {
            TextField("role.name", text: $name)
                .help("role.name_placeholder.help".localized)

            Section("agent.section.role_instructions") {
                TextEditor(text: $prompt)
                    .frame(height: 120)
                    .font(.system(.body, design: .monospaced))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }

            Section("agent.color") {
                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 6), spacing: 8) {
                    ForEach(colorOptions, id: \.self) { c in
                        Button { color = c } label: {
                            Circle()
                                .fill(Color(hex: c) ?? .blue)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle().stroke(Color.white, lineWidth: color == c ? 2.5 : 0)
                                )
                                .shadow(color: color == c ? (Color(hex: c) ?? .blue).opacity(0.4) : .clear, radius: 3)
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
                                .font(.system(size: 13))
                                .frame(width: 28, height: 28)
                                .background(icon == i ? Color.accentColor.opacity(0.2) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }

    // MARK: - 指令预览 Tab（CLAUDE.md / AGENTS.md 预览）

    @ViewBuilder
    private var roleInstructionPreviewTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 预览说明
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("agent.role.inject_hint")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // 文件预览
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                    Text(verbatim: "CLAUDE.md / AGENTS.md")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

                ScrollView {
                    Text(generatedFileContent)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
            }

            // 存储路径提示
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                Text(roleDirectoryPath)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 生成的文件内容预览
    private var generatedFileContent: String {
        let rolePrompt = prompt.isEmpty ? "agent.role_prompt.placeholder".localized : prompt
        return """
        <your_assigned_role>
        \(rolePrompt)
        </your_assigned_role>

        <working_directory>
        IMPORTANT: You were started in this directory to receive the above role assignment. The actual project you should be working on is located at:
        {工作区目录}
        </working_directory>
        """
    }

    /// 角色文件存储路径
    private var roleDirectoryPath: String {
        let id = role?.id ?? UUID()
        return "~/.open-maestri/roles/\(id.uuidString.prefix(8))…/"
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
