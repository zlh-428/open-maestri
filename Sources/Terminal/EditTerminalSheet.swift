import SwiftUI
import AppKit

/// 用于 Sheet 呈现的 Identifiable 包装
struct EditTerminalItem: Identifiable {
    let id: UUID
    let content: TerminalContent
}

/// 编辑终端节点 Sheet（名称、命令、Maestro 模式）
struct EditTerminalSheet: View {
    let nodeId: UUID
    let content: TerminalContent
    let workspace: WorkspaceManager
    let onDismiss: () -> Void
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var command: String
    @State private var isManager: Bool

    enum Field: Hashable { case name, command }
    @FocusState private var focusedField: Field?

    init(nodeId: UUID, content: TerminalContent, workspace: WorkspaceManager, onDismiss: @escaping () -> Void) {
        self.nodeId = nodeId
        self.content = content
        self.workspace = workspace
        self.onDismiss = onDismiss
        _name = State(initialValue: content.name)
        _command = State(initialValue: content.command)
        _isManager = State(initialValue: content.isManager)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("terminal.edit.title").font(.headline)
                Spacer()
                Button("button.cancel") { dismiss(); onDismiss() }.keyboardShortcut(.escape)
                Button("button.save") { save(); dismiss(); onDismiss() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }.padding()
            Divider()
            Form {
                TextField("agent.name", text: $name)
                    .focused($focusedField, equals: .name)
                TextField("terminal.launch_command", text: $command)
                    .focused($focusedField, equals: .command)
                    .help("terminal.edit.command_help".localized)
                Toggle("terminal.maestro_mode", isOn: $isManager)
                    .help("terminal.edit.maestro_help".localized)
            }.formStyle(.grouped).padding()
        }
        .frame(width: 380, height: 240)
        .task { activateFirstTextField() }
    }

    private func save() {
        guard let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .terminal(var tc) = workspace.nodes[idx].content else { return }
        tc.name = name
        tc.command = command
        tc.isManager = isManager
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
