import SwiftUI

@main
struct OpenMaestriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @State private var l10n = LocalizationManager.shared
    @State private var showRoutines = false
    @State private var showCreateWorkspace = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(\.locale, l10n.locale)
                .task {
                    // 将 appState 绑定到 AppDelegate，供退出时访问
                    appDelegate.appState = appState
                    await appState.loadOnLaunch()
                    // 启动后同步语言设置到 LocalizationManager
                    LocalizationManager.shared.sync(from: appState.preferences.language)
                    appState.startAutosave()
                    BackupManager.shared.startHourlyBackups()
                    // InterAgentServer 已在 AppDelegate.applicationDidFinishLaunching 启动
                    try? RoutineScheduler.shared.loadRoutines()
                    // Spotlight: 重建索引
                    let wsNodes = Dictionary(
                        uniqueKeysWithValues: appState.workspaces.map { ws in
                            (ws.id, ws.nodes)
                        }
                    )
                    SpotlightIndexer.shared.rebuildIndex(
                        workspaces: appState.manifest.workspaces,
                        nodes: wsNodes
                    )
                }
                .onDisappear {
                    // 注意：主要清理逻辑已移至 AppDelegate.applicationShouldTerminate
                    // 此处仅作为窗口关闭的备份清理（非退出场景时触发）
                    appState.stopAutosave()
                    BackupManager.shared.stopBackups()
                }
                .sheet(isPresented: $showRoutines) {
                    RoutineManagerView()
                        .environment(appState)
                        .environment(\.locale, l10n.locale)
                }
        }
        .commands {
            // MARK: File 菜单
            CommandGroup(after: .newItem) {
                Button("menu.app.new_workspace") {
                    NotificationCenter.default.post(name: .showCreateWorkspace, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("menu.app.routines") {
                    showRoutines = true
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
            }

            // MARK: View 菜单
            CommandMenu("menu.view") {
                Button("menu.view.toggle_zoom") {
                    NotificationCenter.default.post(name: .toggleCanvasZoom, object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("menu.view.floor_overview") {
                    NotificationCenter.default.post(name: .showFloorOverview, object: nil)
                }
                .keyboardShortcut("\\", modifiers: [.command, .shift])

                Divider()

                Button("menu.view.zoom_in") {
                    NotificationCenter.default.post(name: .canvasZoomIn, object: nil)
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("menu.view.zoom_out") {
                    NotificationCenter.default.post(name: .canvasZoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("menu.view.reset_zoom") {
                    NotificationCenter.default.post(name: .canvasZoomReset, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("menu.view.filter_search") {
                    NotificationCenter.default.post(name: .showCanvasFilter, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)

                Divider()

                Button("menu.view.open_in_editor") {
                    NotificationCenter.default.post(name: .openInEditor, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            // MARK: Window 菜单補充
            CommandGroup(after: .windowSize) {
                Button("menu.view.next_workspace") {
                    NotificationCenter.default.post(name: .nextWorkspace, object: nil)
                }
                .keyboardShortcut(.downArrow, modifiers: .command)

                Button("menu.view.prev_workspace") {
                    NotificationCenter.default.post(name: .prevWorkspace, object: nil)
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                Divider()

                Button("menu.view.next_terminal") {
                    NotificationCenter.default.post(name: .nextTerminal, object: nil)
                }
                .keyboardShortcut(.tab, modifiers: .control)

                Button("menu.view.prev_terminal") {
                    NotificationCenter.default.post(name: .prevTerminal, object: nil)
                }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            }
        }

        Settings {
            SettingsWindow()
                .environment(appState)
                .environment(\.locale, l10n.locale)
        }
    }
}
