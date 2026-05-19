import SwiftUI
import AppKit

struct ShortcutsSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var capturingActionId: String? = nil

    private let actions: [ShortcutAction] = [
        ShortcutAction(id: "switchWorkspaceUp",   nameKey: "shortcut.switch_workspace_up",   defaultKey: "⌘↑"),
        ShortcutAction(id: "switchWorkspaceDown",  nameKey: "shortcut.switch_workspace_down",  defaultKey: "⌘↓"),
        ShortcutAction(id: "focusTerminal",        nameKey: "shortcut.focus_terminal",         defaultKey: "⌘1-9"),
        ShortcutAction(id: "cycleTerminalNext",    nameKey: "shortcut.cycle_terminal_next",    defaultKey: "⌃Tab"),
        ShortcutAction(id: "cycleTerminalPrev",    nameKey: "shortcut.cycle_terminal_prev",    defaultKey: "⌃⇧Tab"),
        ShortcutAction(id: "centerNode",           nameKey: "shortcut.center_node",            defaultKey: "\\"),
        ShortcutAction(id: "deleteNode",           nameKey: "shortcut.delete_node",            defaultKey: "⌘W"),
        ShortcutAction(id: "connectNodes",         nameKey: "shortcut.connect_nodes",          defaultKey: "⌘L"),
        ShortcutAction(id: "toggleScrollLock",     nameKey: "shortcut.toggle_scroll_lock",     defaultKey: "⌘⇧B"),
        ShortcutAction(id: "floorOverview",        nameKey: "shortcut.floor_overview",         defaultKey: "⌘⇧\\"),
        ShortcutAction(id: "filterSearch",         nameKey: "shortcut.filter_search",          defaultKey: "⌘P"),
        ShortcutAction(id: "openSettings",         nameKey: "shortcut.open_settings",          defaultKey: "⌘,"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Table(actions) {
                TableColumn("shortcut.action") { action in
                    Text(LocalizedStringKey(action.nameKey)).font(.body)
                }
                TableColumn("shortcut.key") { action in
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
                            Text("shortcut.press_new").font(.caption).foregroundStyle(.secondary)
                            Button("button.cancel") { capturingActionId = nil }.controlSize(.small)
                        } else {
                            Button("button.modify") { capturingActionId = action.id }.controlSize(.small)
                        }
                    }
                }
            }
            .frame(minWidth: 500, minHeight: 300)

            HStack {
                Spacer()
                Button("button.restore_defaults") { resetAll() }.buttonStyle(.bordered)
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
    let nameKey: String
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
