import SwiftUI

/// 全局设置窗口（Story 1.6 实现完整内容）
struct SettingsWindow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environment(appState)
                .tabItem { Label("settings.tab.general", systemImage: "gearshape") }
            AgentsSettingsView()
                .environment(appState)
                .tabItem { Label("settings.tab.agents", systemImage: "cpu") }
            TerminalSettingsView()
                .environment(appState)
                .tabItem { Label("settings.tab.terminal", systemImage: "terminal") }
            ShortcutsSettingsView()
                .environment(appState)
                .tabItem { Label("settings.tab.shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 560, height: 420)
    }
}
