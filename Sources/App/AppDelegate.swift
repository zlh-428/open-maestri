import OSLog
import AppKit
import Foundation
import Sparkle

/// AppDelegate 处理应用生命周期事件
class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger.make(category: "AppDelegate")
    weak var appState: AppState?

    // MARK: - Sparkle 自动更新
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. InterAgentServer 必须在任何终端创建前启动（消除 port=0 竞态）
        do {
            try InterAgentServer.shared.start()
            logger.info("InterAgentServer started on port \(InterAgentServer.shared.port)")
        } catch {
            logger.error("InterAgentServer failed to start: \(error)")
        }

        // 2. Sparkle 自动更新（Debug 构建跳过自动检查，避免签名/appcast 缺失报错）
        #if DEBUG
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #else
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
        logger.debug("Application did finish launching")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.debug("Application will terminate — forcing save")
        guard let appState else { return }

        // 停止 autosave timer 避免与同步保存冲突
        appState.stopAutosave()

        // 同步保存所有工作区（applicationWillTerminate 在主线程同步调用）
        for ws in appState.workspaces {
            do {
                try ws.saveSync()
            } catch {
                logger.error("Failed to save workspace \(ws.id) on terminate: \(error)")
            }
        }

        // 保存 app state
        do {
            var stateData = AppStateData()
            stateData.activeWorkspaceId = appState.activeWorkspaceId
            stateData.hasCompletedOnboarding = appState.hasCompletedOnboarding
            stateData.cleanShutdown = true
            try PersistenceManager.shared.saveAppState(stateData)
        } catch {
            logger.error("Failed to save app state on terminate: \(error)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - 检查更新（供 Settings 调用）
    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
