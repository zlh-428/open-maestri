import OSLog
import Foundation

/// 全局应用状态，使用 @Observable（macOS 14+）
@Observable
final class AppState {
    var activeWorkspaceId: UUID?
    var workspaces: [WorkspaceManager] = []
    var preferences: Preferences = Preferences()
    var hasCompletedOnboarding: Bool = false
    var needsRecovery: Bool = false
    var loadErrors: [String] = []
    var manifest: WorkspaceManifest = WorkspaceManifest()
    /// 最近访问的工作区 ID（最多 5 个，供⌘⌘数字跳转使用）
    var recentWorkspaceIds: [UUID] = []

    private let logger = Logger.make(category: "AppState")
    private let pm = PersistenceManager.shared

    init() {}

    // MARK: - 启动加载（NFR1：冷启动 < 1.5s）

    func loadOnLaunch() async {
        do {
            try pm.ensureDirectoriesExist()
            let stateData = try pm.loadAppState()
            await MainActor.run {
                activeWorkspaceId = stateData.activeWorkspaceId
                hasCompletedOnboarding = stateData.hasCompletedOnboarding
                needsRecovery = !stateData.cleanShutdown
                recentWorkspaceIds = stateData.recentWorkspaceIds
            }
            let prefs = try pm.loadPreferences()
            await MainActor.run { preferences = prefs }
            let man = try pm.loadManifest()
            await MainActor.run { manifest = man }

            // 加载所有工作区
            var loadedWorkspaces: [WorkspaceManager] = []
            var errors: [String] = []
            for entry in man.workspaces {
                let ws = WorkspaceManager(entry: entry)
                do {
                    try ws.load()
                } catch {
                    errors.append("工作区 \"\(entry.name)\" 加载失败: \(error.localizedDescription)")
                    logger.error("Workspace \(entry.id) load error: \(error)")
                }
                loadedWorkspaces.append(ws)
            }
            await MainActor.run {
                workspaces = loadedWorkspaces
                loadErrors = errors
            }

            // 标记本次为未完成关闭
            var dirty = stateData
            dirty.cleanShutdown = false
            try pm.saveAppState(dirty)
            logger.debug("App state loaded — workspaces: \(man.workspaces.count)")
        } catch {
            logger.error("Failed to load app state: \(error)")
        }
    }

    // MARK: - 自动保存（NFR5：不阻塞 UI，Story 1.5）

    private var autosaveTimer: Timer?

    func startAutosave() {
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: Constants.autosaveInterval, repeats: true) { [weak self] _ in
            Task.detached(priority: .background) { [weak self] in
                await self?.autosave()
            }
        }
    }

    func stopAutosave() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
    }

    private func autosave() async {
        do {
            try pm.saveManifest(manifest)
            try pm.savePreferences(preferences)
            // 保存所有工作区（节点、连接、画布状态）
            for ws in await MainActor.run(body: { workspaces }) {
                try await ws.save()
            }
            logger.debug("Autosave completed (\(self.workspaces.count) workspaces)")
        } catch {
            logger.error("Autosave failed: \(error)")
        }
    }

    /// 强制同步保存（应用退出时调用）
    func forceSave(cleanShutdown: Bool) {
        do {
            try pm.saveManifest(manifest)
            try pm.savePreferences(preferences)
            var state = AppStateData()
            state.activeWorkspaceId = activeWorkspaceId
            state.hasCompletedOnboarding = hasCompletedOnboarding
            state.cleanShutdown = cleanShutdown
            try pm.saveAppState(state)
        } catch {
            logger.error("Force save failed: \(error)")
        }
    }
}
