import AppKit
import Foundation
import OSLog

/// 终端生命周期管理器
/// - 为每个 Terminal 节点创建/销毁 PTY 会话
/// - **并行启动**：所有终端 PTY 同时 fork，对标 Maestri 快速无卡顿启动
/// - 所有 PTY 写入操作必须通过此类（架构约束）
@MainActor
final class TerminalManager {
    static let shared = TerminalManager()
    private let logger = Logger.make(category: "TerminalManager")

    /// 活跃终端 UUID → 终端状态（跨工作区共存，符合 Maestri 多工作区后台运行设计）
    private(set) var terminals: [UUID: TerminalSession] = [:]
    /// 终端 UUID → 所属工作区 ID（用于按工作区查询）
    private(set) var terminalWorkspaceMap: [UUID: UUID] = [:]
    /// 终端 UUID → SwiftTermProvider（取代旧的 TerminalProviderRegistry）
    private(set) var providers: [UUID: SwiftTermProvider] = [:]
    /// 已完成 shell 初始化的终端 ID 集合
    private(set) var completedProviders: Set<UUID> = []

    private(set) var isShuttingDown = false

    private init() {}

    // MARK: - 终端创建

    func createTerminal(
        id: UUID,
        command: String,
        workingDirectory: String,
        workspaceId: UUID? = nil,
        roleName: String? = nil
    ) -> TerminalSession {
        let session = TerminalSession(
            id: id,
            command: command,
            workingDirectory: workingDirectory,
            roleName: roleName
        )
        terminals[id] = session
        if let wsId = workspaceId {
            terminalWorkspaceMap[id] = wsId
            Task.detached(priority: .background) {
                let store = ScrollbackStore()
                let entries = (try? store.load(terminalId: id, workspaceId: wsId)) ?? []
                if !entries.isEmpty {
                    Task { @MainActor in
                        session.bulkLoadHistory(entries.map { $0.text })
                    }
                }
            }
        }

        // 并行启动：直接创建 provider 并启动 PTY，不排队等待
        startProvider(
            id: id,
            command: command,
            workingDirectory: workingDirectory,
            workspaceId: workspaceId,
            roleName: roleName
        )

        logger.debug("Terminal \(id) created and starting, command: \(command)")
        return session
    }

    /// 便捷方法：通过 AgentPreset 创建终端（用于测试和工具栏）
    @discardableResult
    func createTerminal(
        id: UUID,
        workingDirectory: String,
        preset: AgentPreset,
        workspaceId: UUID? = nil,
        roleName: String? = nil
    ) -> TerminalSession {
        createTerminal(
            id: id,
            command: preset.command,
            workingDirectory: workingDirectory,
            workspaceId: workspaceId,
            roleName: roleName
        )
    }

    /// 补填终端所属工作区映射（用于复用 provider 时 workspaceId 未随 session 传入的情况）
    func registerWorkspace(terminalId: UUID, workspaceId: UUID) {
        terminalWorkspaceMap[terminalId] = workspaceId
    }

    func removeTerminal(id: UUID) {
        providers[id]?.stop()
        providers.removeValue(forKey: id)
        completedProviders.remove(id)
        terminals[id]?.terminate()
        terminals.removeValue(forKey: id)
        terminalWorkspaceMap.removeValue(forKey: id)
        logger.debug("Terminal \(id) removed")
    }

    func shutdown() {
        isShuttingDown = true
        providers.values.forEach { $0.stop() }
        providers.removeAll()
        completedProviders.removeAll()
        terminals.removeAll()
    }

    // MARK: - PTY 写入（所有写入的唯一入口）

    func write(to terminalId: UUID, text: String) {
        guard let session = terminals[terminalId] else {
            logger.warning("Write to unknown terminal \(terminalId)")
            return
        }
        session.write(text)
    }

    func writeLine(to terminalId: UUID, text: String) {
        write(to: terminalId, text: text + "\n")
    }

    // MARK: - 并行启动（每个终端独立启动 PTY，互不等待）

    private func startProvider(
        id: UUID,
        command: String,
        workingDirectory: String,
        workspaceId: UUID?,
        roleName: String?
    ) {
        let provider = SwiftTermProvider(
            terminalId: id,
            command: command,
            workingDirectory: workingDirectory
        )
        provider.serverPort = InterAgentServer.shared.port
        provider.workspaceId = workspaceId
        if let prefs = try? PersistenceManager.shared.loadPreferences() {
            provider.preferredFont = NSFont(name: prefs.terminalFontFamily, size: prefs.terminalFontSize)
                ?? NSFont.monospacedSystemFont(ofSize: prefs.terminalFontSize, weight: .regular)
        }
        providers[id] = provider

        // shellReadyCallback：shell 初始化完成 → 标记 → 发通知（不再阻塞其他终端）
        provider.shellReadyCallback = { [weak self] in
            guard let self else { return }
            self.completedProviders.insert(id)
            if let wsId = workspaceId {
                NotificationCenter.default.post(
                    name: .terminalShellReady,
                    object: nil,
                    userInfo: ["terminalId": id, "workspaceId": wsId]
                )
            }
        }

        // 绑定 PTY 输出 → session.recordOutput，并建立 session 写入通道
        if let session = terminals[id] {
            provider.onDataReceived = { [weak session] text in
                Task { @MainActor in session?.recordOutput(text) }
            }
            // 建立 session → provider 写入路径（PTY 启动后 pendingWrites 需要能发送）
            session.onOutput = { [weak provider] text in provider?.write(text) }
        }

        // 直接启动 PTY（不依赖 TerminalEmbeddedView 是否已 attach）。
        // 对标 Maestri：终端创建时立刻启动 PTY 进程，无 viewport culling 延迟。
        // TerminalEmbeddedView 随后 attach 时走 re-attach 分支（已有 terminalView）。
        provider.start(in: NSRect(x: 0, y: 0, width: 600, height: 400))

        // 通知 TerminalEmbeddedView（如已存在）可以 attach provider 的 terminalView
        NotificationCenter.default.post(
            name: .terminalProviderReady,
            object: nil,
            userInfo: ["terminalId": id]
        )
    }
}

/// 单个终端会话状态
@MainActor
final class TerminalSession {
    let id: UUID
    let command: String
    let workingDirectory: String
    let roleName: String?
    /// Agent 实际分配的名称（来自 OMAESTRI_AGENT_NAME 环境变量，由 MaestroHandlers.recruit 注入）
    var agentName: String?
    /// 终端当前工作目录（由 PTY OSC 7 回调实时更新）
    private(set) var currentDirectory: String?
    private(set) var isRunning: Bool = false
    private(set) var isIdle: Bool = true

    /// PTY 写入回调（TerminalEmbeddedView.makeNSView 后设置）
    var onOutput: ((String) -> Void)? {
        didSet {
            // onOutput 一旦设置，立即 flush 待写队列（解决时序竞态）
            if onOutput != nil && !pendingWrites.isEmpty {
                let pending = pendingWrites
                pendingWrites.removeAll()
                pending.forEach { onOutput?($0) }
            }
        }
    }

    /// onOutput 未就绪时暂存待写文本
    private var pendingWrites: [String] = []

    /// 近期输出环形缓冲区（最多 500 行，供 omaestri check 使用）
    /// 使用环形索引避免 removeFirst 的 O(n) 拷贝开销
    private var outputRing: [String] = []
    private var outputRingStart: Int = 0  // 逻辑起始位置
    private var outputRingCount: Int = 0  // 当前有效行数
    private let bufferMaxLines = 500

    private let activityMonitor = TerminalActivityMonitor()

    init(id: UUID, command: String, workingDirectory: String, roleName: String?) {
        self.id = id
        self.command = command
        self.workingDirectory = workingDirectory
        self.roleName = roleName

        activityMonitor.onStatusChanged = { [weak self] isActive in
            guard let self else { return }
            if !isActive {
                self.markIdle()
            }
        }
        activityMonitor.start()
    }

    func write(_ text: String) {
        if let cb = onOutput {
            cb(text)
        } else {
            // PTY 尚未初始化，暂存到队列（最多缓存 100 条）
            if pendingWrites.count < 100 { pendingWrites.append(text) }
        }
    }

    /// 记录 PTY 输出到缓存（由 SwiftTermProvider 在收到输出时调用）
    func recordOutput(_ text: String) {
        let newLines = text.components(separatedBy: "\n")
        appendToRing(newLines)
        isIdle = false
        activityMonitor.recordOutput()
    }

    /// 批量加载历史记录（仅写入 buffer，不触发 activityMonitor 或 Notification）
    /// 用于 scrollback 恢复场景，避免逐行触发大量副作用
    func bulkLoadHistory(_ lines: [String]) {
        appendToRing(lines)
    }

    /// 获取最近 N 行输出
    func recentOutput(lines: Int = 20) -> String {
        let count = min(lines, outputRingCount)
        guard count > 0 else { return "" }
        var result: [String] = []
        result.reserveCapacity(count)
        // 从环形缓冲区尾部取 count 行
        let startIdx = (outputRingStart + outputRingCount - count) % outputRing.count
        for i in 0..<count {
            result.append(outputRing[(startIdx + i) % outputRing.count])
        }
        return result.joined(separator: "\n")
    }

    // MARK: - Ring Buffer 内部实现

    /// 将新行追加到环形缓冲区（O(1) 均摊，无数组元素移动）
    private func appendToRing(_ newLines: [String]) {
        // 初始化环形缓冲区（首次写入时分配固定容量）
        if outputRing.isEmpty {
            outputRing = Array(repeating: "", count: bufferMaxLines)
        }
        for line in newLines {
            let writeIdx = (outputRingStart + outputRingCount) % bufferMaxLines
            outputRing[writeIdx] = line
            if outputRingCount < bufferMaxLines {
                outputRingCount += 1
            } else {
                // 缓冲区已满，覆盖最旧元素，移动起始指针
                outputRingStart = (outputRingStart + 1) % bufferMaxLines
            }
        }
    }

    /// 标记空闲（由 activityMonitor 回调触发）
    /// 仅当从非空闲切换到空闲时才发出通知（避免重复触发）
    func markIdle() {
        guard !isIdle else { return }
        isIdle = true
        NotificationCenter.default.post(
            name: .terminalBecameIdle,
            object: nil,
            userInfo: ["terminalId": id]
        )
    }

    /// 更新当前工作目录（由 SwiftTermProvider.hostCurrentDirectoryUpdate 调用）
    func updateCurrentDirectory(_ directory: String?) {
        guard let dir = directory, !dir.isEmpty, dir != currentDirectory else { return }
        currentDirectory = dir
        NotificationCenter.default.post(
            name: .terminalDirectoryChanged,
            object: nil,
            userInfo: ["terminalId": id, "directory": dir]
        )
    }

    func terminate() {
        isRunning = false
        activityMonitor.stop()
    }
}
