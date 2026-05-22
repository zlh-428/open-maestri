import SwiftUI
import AppKit

/// 用于 Sheet 呈现的 Identifiable 包装
struct EditTerminalItem: Identifiable {
    let id: UUID
    let content: TerminalContent
}

// MARK: - 编辑终端 Sheet（三 Tab：详细信息、外观、角色）

struct EditTerminalSheet: View {
    let nodeId: UUID
    let content: TerminalContent
    let workspace: WorkspaceManager
    let onDismiss: () -> Void
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case details
        case appearance
        case role
    }

    @State private var selectedTab: Tab = .details

    // 详细信息 Tab
    @State private var name: String
    @State private var command: String
    @State private var monitorActivity: Bool
    @State private var isManager: Bool
    @State private var shortcutMode: ShortcutMode
    @State private var workingDirectory: String

    // 外观 Tab
    @State private var icon: String
    @State private var iconColor: String
    @State private var themeId: String
    @State private var fontFamily: String
    @State private var fontSize: CGFloat

    enum Field: Hashable { case name, command }
    @FocusState private var focusedField: Field?

    init(nodeId: UUID, content: TerminalContent, workspace: WorkspaceManager, onDismiss: @escaping () -> Void) {
        self.nodeId = nodeId
        self.content = content
        self.workspace = workspace
        self.onDismiss = onDismiss
        _name = State(initialValue: content.name)
        _command = State(initialValue: content.command)
        _monitorActivity = State(initialValue: content.monitorWithOmbro)
        _isManager = State(initialValue: content.isManager)
        _shortcutMode = State(initialValue: content.shortcutMode)
        _workingDirectory = State(initialValue: content.workingDirectory)
        _icon = State(initialValue: content.icon)
        _iconColor = State(initialValue: content.color)
        _themeId = State(initialValue: content.themeId ?? "system")
        _fontFamily = State(initialValue: content.fontFamily ?? "SF Mono")
        _fontSize = State(initialValue: content.fontSize ?? 13)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            Text("terminal.edit.title")
                .font(.system(size: 16, weight: .bold))
                .padding(.top, 20)
                .padding(.bottom, 14)

            // Tab 选择器 — 胶囊样式
            EditTerminalTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            // Tab 内容
            Group {
                switch selectedTab {
                case .details:
                    detailsTabView
                case .appearance:
                    appearanceTabView
                case .role:
                    roleTabView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .padding(.horizontal, 20)

            // 底部按钮 — 居中
            HStack(spacing: 12) {
                Button("button.cancel") { dismiss(); onDismiss() }
                    .keyboardShortcut(.escape)
                    .controlSize(.large)
                Button("button.save") { save(); dismiss(); onDismiss() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(.vertical, 16)
        }
        .frame(width: 460, height: 520)
        .task { activateFirstTextField() }
    }

    // MARK: - 详细信息 Tab

    @ViewBuilder
    private var detailsTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 名称（浅灰背景输入框）
            TextField("terminal.name_placeholder", text: $name)
                .focused($focusedField, equals: .name)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // 命令
            HStack(spacing: 10) {
                Text("terminal.command")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                TextField("terminal.command_placeholder", text: $command)
                    .focused($focusedField, equals: .command)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            // 监控活动
            Toggle(isOn: $monitorActivity) {
                HStack(spacing: 5) {
                    Text("terminal.monitor")
                        .font(.system(size: 12))
                    InfoTooltipView(text: "terminal.edit.monitor_help".localized)
                }
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Maestro
            Toggle(isOn: $isManager) {
                HStack(spacing: 5) {
                    Text("terminal.maestro_mode")
                        .font(.system(size: 12))
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(.purple)
                    InfoTooltipView(text: "terminal.edit.maestro_help".localized)
                }
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            // 快捷键
            HStack(spacing: 10) {
                Text("terminal.shortcut")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: $shortcutMode.kind) {
                    ForEach(ShortcutMode.Kind.allCases, id: \.self) { kind in
                        Text(ShortcutMode(kind: kind).displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            // 工作目录
            VStack(alignment: .leading, spacing: 6) {
                Text("terminal.working_directory")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(abbreviatedWorkingDir)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("terminal.browse") {
                        browseWorkingDirectory()
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - 外观 Tab

    @ViewBuilder
    private var appearanceTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 图标
                VStack(alignment: .leading, spacing: 8) {
                    Text("terminal.edit.icon")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    IconPickerView(selectedIcon: $icon)
                }

                // 颜色
                VStack(alignment: .leading, spacing: 8) {
                    Text("terminal.edit.color")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    ColorPickerGridView(selectedColor: $iconColor)
                }

                // 主题
                VStack(alignment: .leading, spacing: 8) {
                    Text("terminal.edit.theme")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    ThemePickerView(selectedThemeId: $themeId)
                }

                // 字体
                VStack(alignment: .leading, spacing: 8) {
                    Text("terminal.edit.font")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    FontPickerView(fontFamily: $fontFamily, fontSize: $fontSize)
                }
            }
            .padding(24)
        }
    }

    // MARK: - 角色 Tab（占位）

    @ViewBuilder
    private var roleTabView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("terminal.edit.role_placeholder")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var abbreviatedWorkingDir: String {
        let home = NSHomeDirectory()
        if workingDirectory.hasPrefix(home) {
            return "~" + workingDirectory.dropFirst(home.count)
        }
        return workingDirectory.isEmpty ? "~" : workingDirectory
    }

    private func browseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: workingDirectory.isEmpty ? NSHomeDirectory() : workingDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }

    private func save() {
        guard let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .terminal(var tc) = workspace.nodes[idx].content else { return }
        tc.name = name
        tc.command = command
        tc.monitorWithOmbro = monitorActivity
        tc.isManager = isManager
        tc.shortcutMode = shortcutMode
        tc.workingDirectory = workingDirectory
        tc.icon = icon
        tc.color = iconColor
        tc.themeId = themeId
        tc.fontFamily = fontFamily
        tc.fontSize = fontSize
        let newContent = NodeContent.terminal(tc)
        workspace.nodes[idx].content = newContent
        NotificationCenter.default.post(
            name: .canvasNodeContentChanged,
            object: nil,
            userInfo: ["nodeId": nodeId, "content": newContent]
        )
        Task { try? await workspace.save() }
    }
}

// MARK: - 自定义 Tab 栏（胶囊样式，匹配 Maestri UI）

struct EditTerminalTabBar: View {
    @Binding var selectedTab: EditTerminalSheet.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EditTerminalSheet.Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tabTitle(tab))
                        .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule()
                                .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            Capsule()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func tabTitle(_ tab: EditTerminalSheet.Tab) -> String {
        switch tab {
        case .details: return "terminal.edit.tab.details".localized
        case .appearance: return "terminal.edit.tab.appearance".localized
        case .role: return "terminal.edit.tab.role".localized
        }
    }
}

// MARK: - Info Tooltip View

struct InfoTooltipView: View {
    let text: String

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .help(text)
    }
}

// MARK: - Icon Picker View

struct IconPickerView: View {
    @Binding var selectedIcon: String

    private let icons: [String] = [
        "face.smiling", "terminal", "star", "hare",
        "sparkle", "bubble.left.and.bubble.right", "gearshape", "rectangle",
        "server.rack", "globe", "hammer", "wrench",
        "bolt", "tray.full", "desktopcomputer", "rectangle.inset.filled",
        "display", "paintbrush", "folder", "doc",
        "shield", "cube", "eye", "wand.and.stars"
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 9), spacing: 4) {
            ForEach(icons, id: \.self) { iconName in
                Button {
                    selectedIcon = iconName
                } label: {
                    Image(systemName: iconName)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedIcon == iconName ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selectedIcon == iconName ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: selectedIcon == iconName ? 1.5 : 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Color Picker Grid View

struct ColorPickerGridView: View {
    @Binding var selectedColor: String

    private let colors: [(String, Color)] = [
        ("#007AFF", .blue),
        ("#FF3B30", .red),
        ("#34C759", .green),
        ("#FF9500", .orange),
        ("#AF52DE", .purple),
        ("#FF2D55", .pink),
        ("#5AC8FA", .cyan),
        ("#FFCC00", .yellow),
        ("#8E8E93", .gray),
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(colors, id: \.0) { hex, color in
                Button {
                    selectedColor = hex
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(selectedColor == hex ? 0.9 : 0), lineWidth: 2.5)
                                .padding(-3)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Theme Picker View

struct ThemePickerView: View {
    @Binding var selectedThemeId: String

    private let themes: [(id: String, name: String, bg: Color, fg: Color)] = [
        ("system", "terminal.theme.system".localized, Color(white: 0.97), .blue),
        ("maestri-dark", "terminal.theme.dark".localized, Color(white: 0.12), .green),
        ("maestri-light", "terminal.theme.light".localized, .white, .blue),
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(themes, id: \.id) { theme in
                Button {
                    selectedThemeId = theme.id
                } label: {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.bg)
                            .frame(width: 86, height: 54)
                            .overlay(
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("~/dev")
                                        .font(.system(size: 9, design: .monospaced))
                                    HStack(spacing: 2) {
                                        Text("$")
                                            .font(.system(size: 9, design: .monospaced))
                                        Rectangle()
                                            .fill(theme.fg)
                                            .frame(width: 5, height: 11)
                                    }
                                }
                                .foregroundStyle(theme.id == "maestri-dark" ? .white : .primary)
                                .padding(8)
                                , alignment: .topLeading
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedThemeId == theme.id ? Color.accentColor : Color(white: 0.8), lineWidth: selectedThemeId == theme.id ? 2 : 0.5)
                            )
                        Text(theme.name)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            // 自定义占位
            Button {
                // TODO: 自定义主题
            } label: {
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color(white: 0.7))
                        .frame(width: 86, height: 54)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        )
                    Text("terminal.theme.custom".localized)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Font Picker View

struct FontPickerView: View {
    @Binding var fontFamily: String
    @Binding var fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(fontFamily)  \(Int(fontSize))pt")
                    .font(.system(size: 13))
                Spacer()
                Button("terminal.edit.font_choose") {
                    showFontPanel()
                }
                .controlSize(.small)
            }

            // 预览 — 灰色背景框，左对齐
            HStack {
                Text("abc 012 →|←")
                    .font(.custom(fontFamily, size: fontSize))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func showFontPanel() {
        let panel = NSFontPanel.shared
        let manager = NSFontManager.shared
        let font = NSFont(name: fontFamily, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        manager.setSelectedFont(font, isMultiple: false)
        panel.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Sheet TextField 激活（共用于所有带 TextField 的 Sheet）

/// 激活 sheet 内第一个 TextField，同时 deactivate 主窗口所有
/// NSTextInputClient（SwiftTerm TerminalView）的 input context，
/// 防止 TSM 把键盘事件路由给后台终端。
func activateFirstTextField() {
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(100))

        guard let sheetWin = NSApp.windows.first(where: { $0.isSheet }) else { return }
        guard let parentWin = sheetWin.sheetParent else { return }

        // ── 核心修复 ──────────────────────────────────────────────────────────
        // SwiftTerm 的 TerminalView 实现了 NSTextInputClient。
        // 即使它不是 first responder，TSM（Text Services Manager）可能仍然
        // 持有它的 NSTextInputContext 为 active 状态，导致键盘事件被路由给它
        // 而不是 sheet 内的 TextField，且 local event monitor 完全收不到事件。
        //
        // 修复：找到主窗口里所有 NSTextInputClient view，
        // 强制调用 NSTextInputContext.deactivate()，让 TSM 释放这些 context。
        // ─────────────────────────────────────────────────────────────────────
        deactivateAllTextInputClients(in: parentWin)

        // 激活 sheet 内第一个 NSTextField 的 field editor
        if let tf = firstEditableTextField(in: sheetWin.contentView) {
            sheetWin.makeFirstResponder(tf)
            tf.selectText(nil)
        }
    }
}

/// 遍历 window 内所有 NSView，对实现了 NSTextInputClient 的 view
/// 调用其 inputContext 的 deactivate()，释放 TSM 持有的 active context。
private func deactivateAllTextInputClients(in window: NSWindow) {
    func walk(_ view: NSView) {
        if view is NSTextInputClient {
            view.inputContext?.deactivate()
        }
        for sub in view.subviews { walk(sub) }
    }
    if let root = window.contentView { walk(root) }
}

private func firstEditableTextField(in view: NSView?) -> NSTextField? {
    guard let view else { return nil }
    if let tf = view as? NSTextField, tf.isEditable, !tf.isHidden, tf.alphaValue > 0 {
        return tf
    }
    for sub in view.subviews {
        if let found = firstEditableTextField(in: sub) { return found }
    }
    return nil
}
