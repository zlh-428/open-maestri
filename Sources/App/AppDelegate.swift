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

        // 2. 写入 omaestri skill 到用户全局 ~/.claude/skills/（幂等，后台执行避免阻塞主线程）
        DispatchQueue.global(qos: .userInitiated).async {
            SkillInjector.shared.installSkillsIfNeeded()
        }

        // 3. 配置主窗口样式（透明 title bar，让画布充满窗口）
        DispatchQueue.main.async {
            WindowStateObserver.shared.configureMainWindow()
        }

        // 4. Sparkle 自动更新（Debug 构建跳过自动检查，避免签名/appcast 缺失报错）
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        logger.debug("Application should terminate — starting graceful shutdown")
        guard let appState else { return .terminateNow }

        // 1. 立刻停止所有可能阻塞主线程的子系统
        appState.stopAutosave()
        InterAgentServer.shared.stop()
        RoutineScheduler.shared.stopAllTimers()

        // 2. 在主线程快照所有 @Observable 状态为纯值类型（O(n) 拷贝，无 I/O）
        let payloads: [(id: UUID, doc: WorkspaceDocument)] = appState.workspaces.map { ws in
            (ws.id, WorkspaceDocument(payload: ws.snapshotPayload()))
        }
        let stateData: AppStateData = {
            var s = AppStateData()
            s.activeWorkspaceId = appState.activeWorkspaceId
            s.hasCompletedOnboarding = appState.hasCompletedOnboarding
            s.cleanShutdown = true
            s.recentWorkspaceIds = appState.recentWorkspaceIds
            return s
        }()
        let manifest = appState.manifest

        // 3. 后台线程做 I/O，完成后回调 reply
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
            self?.logger.debug("Graceful shutdown save completed")
            // 通知 AppKit 可以安全退出了
            DispatchQueue.main.async {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }

        // 告诉 AppKit "稍后回复"，不阻塞主线程
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 所有清理已在 applicationShouldTerminate 完成
        // 此处仅做最终资源释放（PTY 进程等）
        logger.debug("Application will terminate — final cleanup")
        TerminalManager.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - 检查更新（供 Settings 调用）
    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
