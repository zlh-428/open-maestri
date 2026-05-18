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

        // 在主线程先把所有 @Observable 属性快照为纯值类型，
        // 再交给后台线程做 I/O，避免跨线程访问 @Observable 对象导致死锁
        let payloads: [(id: UUID, doc: WorkspaceDocument)] = appState.workspaces.map { ws in
            let payload = ws.snapshotPayload()
            return (ws.id, WorkspaceDocument(payload: payload))
        }
        let stateData: AppStateData = {
            var s = AppStateData()
            s.activeWorkspaceId = appState.activeWorkspaceId
            s.hasCompletedOnboarding = appState.hasCompletedOnboarding
            s.cleanShutdown = true
            return s
        }()
        let manifest = appState.manifest

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let pm = PersistenceManager.shared
            for item in payloads {
                do { try pm.saveSync(item.doc, to: pm.workspaceURL(id: item.id)) }
                catch { self?.logger.error("Failed to save workspace \(item.id) on terminate: \(error)") }
            }
            do { try pm.saveManifest(manifest) }
            catch { self?.logger.error("Failed to save manifest on terminate: \(error)") }
            do { try pm.saveAppState(stateData) }
            catch { self?.logger.error("Failed to save app state on terminate: \(error)") }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3.0)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - 检查更新（供 Settings 调用）
    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
