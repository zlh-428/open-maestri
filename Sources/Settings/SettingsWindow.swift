import SwiftUI

/// 全局设置窗口（Story 1.6 实现完整内容）
struct SettingsWindow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environment(appState)
                .tabItem { Label("通用", systemImage: "gearshape") }
            AgentsSettingsView()
                .environment(appState)
                .tabItem { Label("Agents", systemImage: "cpu") }
            TerminalSettingsView()
                .environment(appState)
                .tabItem { Label("终端", systemImage: "terminal") }
            ShortcutsSettingsView()
                .environment(appState)
                .tabItem { Label("快捷键", systemImage: "keyboard") }
        }
        .frame(width: 560, height: 420)
    }
}
