import SwiftUI
import AppKit

struct ShortcutsSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var capturingActionId: String? = nil

    private let actions: [ShortcutAction] = [
        ShortcutAction(id: "switchWorkspaceUp",   name: "切换上一个工作区",    defaultKey: "⌘↑"),
        ShortcutAction(id: "switchWorkspaceDown",  name: "切换下一个工作区",    defaultKey: "⌘↓"),
        ShortcutAction(id: "focusTerminal",        name: "跳转终端（⌘+数字）", defaultKey: "⌘1-9"),
        ShortcutAction(id: "cycleTerminalNext",    name: "下一个终端",         defaultKey: "⌃Tab"),
        ShortcutAction(id: "cycleTerminalPrev",    name: "上一个终端",         defaultKey: "⌃⇧Tab"),
        ShortcutAction(id: "centerNode",           name: "居中选中节点",       defaultKey: "\\"),
        ShortcutAction(id: "deleteNode",           name: "删除选中节点",       defaultKey: "⌘W"),
        ShortcutAction(id: "connectNodes",         name: "开始连线",           defaultKey: "⌘L"),
        ShortcutAction(id: "toggleScrollLock",     name: "锁定/解锁自动滚动",  defaultKey: "⌘⇧B"),
        ShortcutAction(id: "floorOverview",        name: "Floor 总览",        defaultKey: "⌘⇧\\"),
        ShortcutAction(id: "filterSearch",         name: "过滤/搜索",          defaultKey: "⌘P"),
        ShortcutAction(id: "openSettings",         name: "打开设置",           defaultKey: "⌘,"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Table(actions) {
                TableColumn("操作") { action in
                    Text(action.name).font(.body)
                }
                TableColumn("快捷键") { action in
                    HStack {
                        Text(currentKey(for: action))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(capturingActionId == action.id ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).strokeBorder(
                                capturingActionId == action.id ? Color.accentColor : Color.secondary.opacity(0.3),
                                lineWidth: 1
                            ))
                        if capturingActionId == action.id {
                            Text("按下新快捷键…").font(.caption).foregroundStyle(.secondary)
                            Button("取消") { capturingActionId = nil }.controlSize(.small)
                        } else {
                            Button("修改") { capturingActionId = action.id }.controlSize(.small)
                        }
                    }
                }
            }
            .frame(minWidth: 500, minHeight: 300)

            HStack {
                Spacer()
                Button("恢复默认") { resetAll() }.buttonStyle(.bordered)
            }
            .padding()
        }
        .background(KeyCaptureView(isCapturing: capturingActionId != nil) { key in
            if let actionId = capturingActionId {
                saveKey(key, for: actionId)
                capturingActionId = nil
            }
        })
    }

    private func currentKey(for action: ShortcutAction) -> String {
        appState.preferences.shortcuts.customKeys[action.id] ?? action.defaultKey
    }

    private func saveKey(_ key: String, for actionId: String) {
        var prefs = appState.preferences
        prefs.shortcuts.customKeys[actionId] = key
        appState.preferences = prefs
        try? PersistenceManager.shared.savePreferences(prefs)
    }

    private func resetAll() {
        var prefs = appState.preferences
        prefs.shortcuts.customKeys.removeAll()
        appState.preferences = prefs
        try? PersistenceManager.shared.savePreferences(prefs)
    }
}

struct ShortcutAction: Identifiable {
    let id: String
    let name: String
    let defaultKey: String
}

// MARK: - Key Capture View（透明 NSView 捕获键盘事件）

struct KeyCaptureView: NSViewRepresentable {
    let isCapturing: Bool
    let onKey: (String) -> Void

    final class Coordinator: NSObject {
        var monitor: Any?
        var onKey: (String) -> Void
        init(onKey: @escaping (String) -> Void) { self.onKey = onKey }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onKey: onKey) }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKey = onKey
        if isCapturing && context.coordinator.monitor == nil {
            context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let key = shortcutString(event)
                context.coordinator.onKey(key)
                return nil
            }
        } else if !isCapturing, let m = context.coordinator.monitor {
            NSEvent.removeMonitor(m)
            context.coordinator.monitor = nil
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let m = coordinator.monitor { NSEvent.removeMonitor(m) }
    }

    private func shortcutString(_ event: NSEvent) -> String {
        var parts: [String] = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { parts.append("⌘") }
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
            parts.append(chars)
        }
        return parts.joined()
    }
}
