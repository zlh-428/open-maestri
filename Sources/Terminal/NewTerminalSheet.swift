import SwiftUI

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
            Text("terminal.new")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 16)
                .padding(.bottom, 12)

            // MARK: 快速开始 - Agent 图标行
            VStack(alignment: .leading, spacing: 8) {
                Text("onboarding.quick_start")
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
                Text("label.details").tag(0)
                Text("label.appearance").tag(1)
                Text("role.tab").tag(2)
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
                Button("button.cancel") { dismiss() }
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

                Button("button.create") {
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
            Text("terminal.name")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("terminal.name_placeholder", text: $terminalName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($focusedField, equals: .name)
        }

        // 命令
        VStack(alignment: .leading, spacing: 4) {
            Text("terminal.command")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("terminal.command_placeholder", text: $command)
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
                    Text("terminal.monitor")
                        .font(.system(size: 12))
                }
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $isMaestroMode) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(.purple)
                    Text(verbatim: "Maestro")
                        .font(.system(size: 12))
                }
            }
            .toggleStyle(.checkbox)
            .help("terminal.maestro_recruit_help".localized)
        }
        .padding(.top, 4)

        // 工作目录（只读显示 + 选择按钮）
        VStack(alignment: .leading, spacing: 4) {
            Text("workspace.working_dir")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(workingDirectory.isEmpty ? "workspace.working_dir.none".localized : abbreviatePath(workingDirectory))
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

                Button("button.choose_directory") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.directoryURL = URL(fileURLWithPath: workingDirectory)
                    panel.begin { response in
                        guard response == .OK, let url = panel.url else { return }
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
                Text("general.appearance.coming_soon")
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
                RoleOptionRow(name: "role.none".localized, icon: "xmark.circle", color: "#8E8E93",
                        isSelected: selectedRoleIdx == nil)
            }
            .buttonStyle(.plain)

            if roles.isEmpty {
                Text("role.no_custom_roles")
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

struct AgentIconButton: View {
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

struct RoleOptionRow: View {
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
