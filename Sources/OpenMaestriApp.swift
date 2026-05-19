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
                    appState.stopAutosave()
                    appState.forceSave(cleanShutdown: true)
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
                Button("New Workspace") {
                    NotificationCenter.default.post(name: .showCreateWorkspace, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Routines…") {
                    showRoutines = true
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
            }

            // MARK: View 菜单
            CommandMenu("View") {
                Button("Toggle Zoom") {
                    NotificationCenter.default.post(name: .toggleCanvasZoom, object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("Floor Overview") {
                    NotificationCenter.default.post(name: .showFloorOverview, object: nil)
                }
                .keyboardShortcut("\\", modifiers: [.command, .shift])

                Divider()

                Button("Zoom In") {
                    NotificationCenter.default.post(name: .canvasZoomIn, object: nil)
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .canvasZoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Zoom") {
                    NotificationCenter.default.post(name: .canvasZoomReset, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Filter / Search") {
                    NotificationCenter.default.post(name: .showCanvasFilter, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)

                Divider()

                Button("Open in Editor") {
                    NotificationCenter.default.post(name: .openInEditor, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            // MARK: Window 菜单補充
            CommandGroup(after: .windowSize) {
                Button("Next Workspace") {
                    NotificationCenter.default.post(name: .nextWorkspace, object: nil)
                }
                .keyboardShortcut(.downArrow, modifiers: .command)

                Button("Previous Workspace") {
                    NotificationCenter.default.post(name: .prevWorkspace, object: nil)
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                Divider()

                Button("Next Terminal") {
                    NotificationCenter.default.post(name: .nextTerminal, object: nil)
                }
                .keyboardShortcut(.tab, modifiers: .control)

                Button("Previous Terminal") {
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
