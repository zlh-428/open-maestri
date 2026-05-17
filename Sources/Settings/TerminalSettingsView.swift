import SwiftUI
import SwiftTerm

struct TerminalSettingsView: View {
    @Environment(AppState.self) private var appState

    private let fontFamilies = ["SF Mono", "Menlo", "Monaco", "Courier New", "JetBrains Mono", "Fira Code"]
    private let fontSizes: [CGFloat] = [11, 12, 13, 14, 15, 16, 18, 20]

    var body: some View {
        @Bindable var state = appState
        Form {
            Section("字体") {
                Picker("字体", selection: $state.preferences.terminalFontFamily) {
                    ForEach(fontFamilies, id: \.self) { Text($0).tag($0) }
                }
                Picker("字号", selection: $state.preferences.terminalFontSize) {
                    ForEach(fontSizes, id: \.self) { Text("\(Int($0))pt").tag($0) }
                }
                Text("字体变更在新建终端时生效，已有终端需重启。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("主题") {
                Picker("终端主题", selection: $state.preferences.terminalTheme) {
                    Text("跟随系统").tag("system")
                    Text("深色").tag("dark")
                    Text("浅色").tag("light")
                }
                .pickerStyle(.radioGroup)
                Text("主题变更立即应用到所有已打开的终端。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400)
        .onChange(of: appState.preferences.terminalTheme) { _, newTheme in
            applyTheme(newTheme)
            try? PersistenceManager.shared.savePreferences(appState.preferences)
        }
        .onChange(of: appState.preferences.terminalFontFamily) { _, _ in
            try? PersistenceManager.shared.savePreferences(appState.preferences)
        }
        .onChange(of: appState.preferences.terminalFontSize) { _, _ in
            try? PersistenceManager.shared.savePreferences(appState.preferences)
        }
    }

    /// 即时应用主题到所有已打开的终端
    private func applyTheme(_ theme: String) {
        let isDark: Bool
        switch theme {
        case "dark":  isDark = true
        case "light": isDark = false
        default:
            isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        Task { @MainActor in
            for provider in allProviders() {
                guard let tv = provider.terminalView else { continue }
                if isDark {
                    tv.configureNativeColors()
                } else {
                    tv.configureNativeColors()
                }
            }
        }
    }

    private func allProviders() -> [SwiftTermProvider] {
        TerminalManager.shared.terminals.keys.compactMap {
            TerminalProviderRegistry.shared.provider(for: $0)
        }
    }
}
