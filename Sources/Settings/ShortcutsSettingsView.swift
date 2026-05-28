import OSLog
import SwiftUI
import AppKit

private let settingsLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "open-maestri", category: "Settings")

// MARK: - Data Model

struct ShortcutAction: Identifiable {
    let id: String
    let nameKey: String
    let descriptionKey: String?
    let defaultKey: String
    /// Individual key symbols for display (each rendered as a separate keycap)
    let keyCaps: [String]

    init(id: String, nameKey: String, descriptionKey: String? = nil, defaultKey: String, keyCaps: [String]) {
        self.id = id
        self.nameKey = nameKey
        self.descriptionKey = descriptionKey
        self.defaultKey = defaultKey
        self.keyCaps = keyCaps
    }
}

struct ShortcutGroup: Identifiable {
    let id: String
    let titleKey: String
    let actions: [ShortcutAction]
}

// MARK: - View

struct ShortcutsSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var filterText: String = ""
    @State private var capturingActionId: String? = nil

    private let groups: [ShortcutGroup] = [
        ShortcutGroup(id: "workspace_nav", titleKey: "shortcut.group.workspace_nav", actions: [
            ShortcutAction(id: "switchWorkspaceDown",  nameKey: "shortcut.switch_workspace_down",  defaultKey: "⌘↓", keyCaps: ["⌘", "↓"]),
            ShortcutAction(id: "switchWorkspaceUp",    nameKey: "shortcut.switch_workspace_up",    defaultKey: "⌘↑", keyCaps: ["⌘", "↑"]),
        ]),
        ShortcutGroup(id: "element_nav", titleKey: "shortcut.group.element_nav", actions: [
            ShortcutAction(id: "cycleTerminalNext",  nameKey: "shortcut.cycle_terminal_next",  defaultKey: "⌃Tab", keyCaps: ["⌃", "Tab"]),
            ShortcutAction(id: "cycleTerminalPrev",  nameKey: "shortcut.cycle_terminal_prev",  defaultKey: "⌃⇧Tab", keyCaps: ["⌃", "⇧", "Tab"]),
            ShortcutAction(id: "centerNode",         nameKey: "shortcut.center_node",           defaultKey: "⌘\\", keyCaps: ["⌘", "\\"]),
            ShortcutAction(
                id: "connectNodes",
                nameKey: "shortcut.connect_nodes",
                descriptionKey: "shortcut.connect_nodes.desc",
                defaultKey: "⌘L",
                keyCaps: ["⌘", "L"]
            ),
            ShortcutAction(id: "deleteNode",         nameKey: "shortcut.delete_node",           defaultKey: "⌘W", keyCaps: ["⌘", "W"]),
            ShortcutAction(
                id: "focusTerminal",
                nameKey: "shortcut.focus_terminal",
                descriptionKey: "shortcut.focus_terminal.desc",
                defaultKey: "⌘1-9",
                keyCaps: ["⌘", "1-9"]
            ),
        ]),
        ShortcutGroup(id: "canvas", titleKey: "shortcut.group.canvas", actions: [
            ShortcutAction(
                id: "zoomScrollModifier",
                nameKey: "shortcut.zoom_scroll_modifier",
                descriptionKey: "shortcut.zoom_scroll_modifier.desc",
                defaultKey: "⌥",
                keyCaps: ["⌥"]
            ),
            ShortcutAction(id: "toggleScrollLock",   nameKey: "shortcut.toggle_scroll_lock",    defaultKey: "⌘⇧B", keyCaps: ["⌘", "⇧", "B"]),
            ShortcutAction(id: "filterSearch",       nameKey: "shortcut.filter_search",         defaultKey: "⌘P", keyCaps: ["⌘", "P"]),
            ShortcutAction(id: "floorOverview",      nameKey: "shortcut.floor_overview",        defaultKey: "⌘⇧\\", keyCaps: ["⌘", "⇧", "\\"]),
            ShortcutAction(id: "openSettings",       nameKey: "shortcut.open_settings",         defaultKey: "⌘,", keyCaps: ["⌘", ","]),
        ]),
    ]

    /// Flattened list of all actions for searching
    private var allActions: [ShortcutAction] {
        groups.flatMap(\.actions)
    }

    /// Filtered groups based on search text
    private var filteredGroups: [ShortcutGroup] {
        guard !filterText.isEmpty else { return groups }
        return groups.compactMap { group in
            let filtered = group.actions.filter { action in
                let name = NSLocalizedString(action.nameKey, comment: "")
                let desc = action.descriptionKey.map { NSLocalizedString($0, comment: "") } ?? ""
                let searchTarget = "\(name) \(desc) \(action.defaultKey)".lowercased()
                return searchTarget.contains(filterText.lowercased())
            }
            guard !filtered.isEmpty else { return nil }
            return ShortcutGroup(id: group.id, titleKey: group.titleKey, actions: filtered)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            // Shortcut list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredGroups) { group in
                        sectionHeader(group.titleKey)
                        ForEach(group.actions) { action in
                            shortcutRow(action)
                            if action.id != group.actions.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }

            Divider()

            // Bottom bar with reset button
            HStack {
                Spacer()
                Button(action: resetAll) {
                    Text("shortcut.restore_defaults")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(KeyCaptureView(isCapturing: capturingActionId != nil) { key in
            if let actionId = capturingActionId {
                saveKey(key, for: actionId)
                capturingActionId = nil
            }
        })
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            TextField("shortcut.filter_placeholder", text: $filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func sectionHeader(_ titleKey: String) -> some View {
        Text(LocalizedStringKey(titleKey))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        HStack(alignment: .center) {
            // Left side: name + description
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(action.nameKey))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                if let descKey = action.descriptionKey {
                    Text(LocalizedStringKey(descKey))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Right side: keycaps
            if capturingActionId == action.id {
                HStack(spacing: 4) {
                    Text("shortcut.press_new")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("button.cancel") {
                        capturingActionId = nil
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
            } else {
                keyCapsView(for: action)
                    .onTapGesture {
                        capturingActionId = action.id
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func keyCapsView(for action: ShortcutAction) -> some View {
        let keys = currentKeyCaps(for: action)
        return HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                keyCap(key)
            }
        }
    }

    private func keyCap(_ symbol: String) -> some View {
        Text(symbol)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 0.5, x: 0, y: 0.5)
    }

    // MARK: - Logic

    private func currentKeyCaps(for action: ShortcutAction) -> [String] {
        if let custom = appState.preferences.shortcuts.customKeys[action.id] {
            return parseKeyCaps(custom)
        }
        return action.keyCaps
    }

    /// Parse a shortcut string like "⌘⇧B" into individual keycap symbols
    private func parseKeyCaps(_ shortcut: String) -> [String] {
        var caps: [String] = []
        var remaining = shortcut
        let modifiers: [Character] = ["⌘", "⌃", "⌥", "⇧"]

        for char in remaining {
            if modifiers.contains(char) {
                caps.append(String(char))
            }
        }
        remaining = String(remaining.filter { !modifiers.contains($0) })
        if !remaining.isEmpty {
            caps.append(remaining)
        }
        return caps.isEmpty ? [shortcut] : caps
    }

    private func saveKey(_ key: String, for actionId: String) {
        var prefs = appState.preferences
        prefs.shortcuts.customKeys[actionId] = key
        appState.preferences = prefs
        do {
            try PersistenceManager.shared.savePreferences(prefs)
        } catch {
            settingsLogger.error("Failed to save preferences: \(error.localizedDescription)")
        }
    }

    private func resetAll() {
        var prefs = appState.preferences
        prefs.shortcuts.customKeys.removeAll()
        appState.preferences = prefs
        do {
            try PersistenceManager.shared.savePreferences(prefs)
        } catch {
            settingsLogger.error("Failed to save preferences: \(error.localizedDescription)")
        }
    }
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
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
            parts.append(chars)
        }
        return parts.joined()
    }
}
