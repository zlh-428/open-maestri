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
    /// 上次自动保存时间（运行时状态，不持久化）
    var lastAutosaveTime: Date?

    private let logger = Logger.make(category: "AppState")
    private let pm = PersistenceManager.shared
    private var idleObserver: NSObjectProtocol?

    init() {
        idleObserver = NotificationCenter.default.addObserver(
            forName: .terminalBecameIdle,
            object: nil,
            queue: nil  // 在 post 线程接收，再通过 Task 跳回 MainActor
        ) { [weak self] notif in
            guard let terminalId = notif.userInfo?["terminalId"] as? UUID else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wsId = TerminalManager.shared.terminalWorkspaceMap[terminalId]
                guard let wsId,
                      let ws = self.workspaces.first(where: { $0.id == wsId }) else { return }
                if wsId != self.activeWorkspaceId {
                    ws.unreadActivityCount += 1
                }
            }
        }
    }

    deinit {
        if let obs = idleObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    /// 切换到某工作区时调用，清零该工作区的未读计数
    func clearUnread(workspaceId: UUID) {
        workspaces.first(where: { $0.id == workspaceId })?.unreadActivityCount = 0
    }

    /// 激活指定工作区：更新 activeWorkspaceId、清零未读计数
    /// Unix socket 为全局固定路径，不随 workspace 切换重建
    func selectWorkspace(id: UUID?) {
        activeWorkspaceId = id
        if let id {
            clearUnread(workspaceId: id)
        }
    }

    // MARK: - 启动加载（NFR1：冷启动 < 1.5s）

    /// Loads all persisted state on cold launch.
    /// - The three root JSON files are read concurrently via `async let`.
    /// - Workspace documents are still loaded sequentially to surface per-workspace errors clearly.
    func loadOnLaunch() async {
        do {
            try pm.ensureDirectoriesExist()

            // Parallel read of the three independent root files
            async let stateTask = Task.detached(priority: .userInitiated) { try self.pm.loadAppState() }.value
            async let prefsTask = Task.detached(priority: .userInitiated) { try self.pm.loadPreferences() }.value
            async let manTask   = Task.detached(priority: .userInitiated) { try self.pm.loadManifest() }.value

            let (stateData, prefs, man) = try await (stateTask, prefsTask, manTask)

            await MainActor.run {
                activeWorkspaceId = stateData.activeWorkspaceId
                hasCompletedOnboarding = stateData.hasCompletedOnboarding
                needsRecovery = !stateData.cleanShutdown
                recentWorkspaceIds = stateData.recentWorkspaceIds
                preferences = prefs
                manifest = man
            }

            // 加载所有工作区（串行，便于逐一捕获错误）
            let loadFailedFormat = await MainActor.run { "workspace.load_failed".localized }
            var loadedWorkspaces: [WorkspaceManager] = []
            var errors: [String] = []
            for entry in man.workspaces {
                let ws = WorkspaceManager(entry: entry)
                do {
                    try ws.load()
                } catch {
                    errors.append(String(format: loadFailedFormat, entry.name, error.localizedDescription))
                    logger.error("Workspace \(entry.id) load error: \(error)")
                }
                loadedWorkspaces.append(ws)
            }
            await MainActor.run {
                workspaces = loadedWorkspaces
                loadErrors = errors
                // 启动全局 Unix socket（应用生命周期内只创建一次）
                InterAgentServer.shared.startUnixSocketIfNeeded()
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
        let interval = TimeInterval(preferences.autosaveIntervalSeconds)
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task.detached(priority: .background) { [weak self] in
                await self?.autosave()
            }
        }
    }

    /// 当用户在设置中修改自动保存间隔时调用，重启 timer
    func restartAutosave() {
        startAutosave()
    }

    func stopAutosave() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
    }

    private func autosave() async {
        do {
            // 在 MainActor 上一次性快照所有主线程可变数据，消除与后台线程的竞态。
            // 将 manifest、preferences 及各脏工作区的 payload 一并复制为值类型快照，
            // 后续 I/O 全部操作快照副本，不再触碰任何 @Observable 属性。
            let (manifestSnapshot, prefsSnapshot, dirtySnapshots):
                (WorkspaceManifest, Preferences, [(WorkspaceManager, WorkspacePayload)]) =
                    await MainActor.run {
                        let dirty = workspaces.filter { $0.isDirty }
                        return (manifest, preferences, dirty.map { ($0, $0.snapshotPayload()) })
                    }

            // 以下为纯序列化 I/O，不再读取任何主线程可变状态
            try pm.saveManifest(manifestSnapshot)
            try pm.savePreferences(prefsSnapshot)
            for (ws, payload) in dirtySnapshots {
                let doc = WorkspaceDocument(payload: payload)
                try await pm.saveWorkspace(doc)
                // isDirty 写回必须在 MainActor 上执行
                await MainActor.run { ws.isDirty = false }
            }
            await MainActor.run { lastAutosaveTime = Date() }
            if !dirtySnapshots.isEmpty {
                logger.debug("Autosave completed (\(dirtySnapshots.count) dirty workspaces saved)")
            }
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
