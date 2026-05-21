import SwiftUI
import SwiftTerm

struct TerminalSettingsView: View {
    @Environment(AppState.self) private var appState

    private let fontFamilies = ["SF Mono", "Menlo", "Monaco", "Courier New", "JetBrains Mono", "Fira Code"]
    private let fontSizes: [CGFloat] = [11, 12, 13, 14, 15, 16, 18, 20]

    var body: some View {
        @Bindable var state = appState
        Form {
            Section("settings.terminal.font") {
                Picker("settings.terminal.font", selection: $state.preferences.terminalFontFamily) {
                    ForEach(fontFamilies, id: \.self) { Text($0).tag($0) }
                }
                Picker("settings.terminal.font_size", selection: $state.preferences.terminalFontSize) {
                    ForEach(fontSizes, id: \.self) { Text("\(Int($0))pt").tag($0) }
                }
                Text("settings.terminal.font.help")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("settings.terminal.theme") {
                Picker("settings.terminal.theme", selection: $state.preferences.terminalTheme) {
                    Text("settings.terminal.theme.system").tag("system")
                    Divider()
                    Text("Maestri Dark").tag("dark")
                    Text("Maestri Light").tag("light")
                    Divider()
                    Text("Dracula").tag("dracula")
                    Text("Solarized Dark").tag("solarized-dark")
                    Text("Solarized Light").tag("solarized-light")
                    Text("Nord").tag("nord")
                    Text("One Dark").tag("one-dark")
                    Text("Tokyo Night").tag("tokyo-night")
                }
                Text("settings.terminal.theme.help")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400)
        .onChange(of: appState.preferences.terminalTheme) { _, newTheme in
            applyThemeToAll(newTheme)
            try? PersistenceManager.shared.savePreferences(appState.preferences)
        }
        .onChange(of: appState.preferences.terminalFontFamily) { _, newFamily in
            applyFontToAll(family: newFamily, size: appState.preferences.terminalFontSize)
            try? PersistenceManager.shared.savePreferences(appState.preferences)
        }
        .onChange(of: appState.preferences.terminalFontSize) { _, newSize in
            applyFontToAll(family: appState.preferences.terminalFontFamily, size: newSize)
            try? PersistenceManager.shared.savePreferences(appState.preferences)
        }
    }

    /// 即时应用主题到所有已打开的终端
    private func applyThemeToAll(_ preference: String) {
        let themeId = TerminalThemeRegistry.resolveThemeId(from: preference)
        Task { @MainActor in
            for provider in allProviders() {
                provider.applyTheme(themeId)
            }
        }
    }

    /// 即时应用字体到所有已打开的终端（无需重启）
    private func applyFontToAll(family: String, size: CGFloat) {
        Task { @MainActor in
            for provider in allProviders() {
                provider.applyFont(family: family, size: size)
            }
        }
    }

    private func allProviders() -> [SwiftTermProvider] {
        Array(TerminalManager.shared.providers.values)
    }
}
