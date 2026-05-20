import Foundation
import OSLog

/// 终端生命周期管理器
/// - 为每个 Terminal 节点创建/销毁 PTY 会话
/// - 所有 PTY 写入操作必须通过此类（架构约束）
@MainActor
final class TerminalManager {
    static let shared = TerminalManager()
    private let logger = Logger.make(category: "TerminalManager")

    /// 活跃终端 UUID → 终端状态（跨工作区共存，符合 Maestri 多工作区后台运行设计）
    private(set) var terminals: [UUID: TerminalSession] = [:]
    /// 终端 UUID → 所属工作区 ID（用于按工作区查询）
    private(set) var terminalWorkspaceMap: [UUID: UUID] = [:]

    private init() {}

    // MARK: - 终端创建

    func createTerminal(
        id: UUID,
        workingDirectory: String,
        preset: AgentPreset,
        role: RolePreset? = nil,
        workspaceId: UUID? = nil
    ) -> TerminalSession {
        // 如果有角色，注入到专属目录下启动
        let startDirectory: String
        if let role {
            startDirectory = RoleInjector.shared.prepareRoleDirectory(
                roleId: role.id,
                rolePrompt: role.prompt,
                workingDirectory: workingDirectory
            )
        } else {
            startDirectory = workingDirectory
        }

        let session = TerminalSession(
            id: id,
            command: preset.command,
            workingDirectory: startDirectory,
            roleName: role?.name
        )
        terminals[id] = session
        if let wsId = workspaceId {
            terminalWorkspaceMap[id] = wsId
            // 加载历史 scrollback 到 outputBuffer（供 omaestri check 使用）
            Task.detached(priority: .background) {
                let store = ScrollbackStore()
                let entries = (try? store.load(terminalId: id, workspaceId: wsId)) ?? []
                if !entries.isEmpty {
                    Task { @MainActor in
                        entries.forEach { session.recordOutput($0.text) }
                    }
                }
            }
        }
        logger.debug("Terminal \(id) created with preset \(preset.name)\(role.map { ", role: \($0.name)" } ?? "")")
        return session
    }

    /// 补填终端所属工作区映射（用于复用 provider 时 workspaceId 未随 session 传入的情况）
    func registerWorkspace(terminalId: UUID, workspaceId: UUID) {
        terminalWorkspaceMap[terminalId] = workspaceId
    }

    func removeTerminal(id: UUID) {
        terminals[id]?.terminate()
        terminals.removeValue(forKey: id)
        terminalWorkspaceMap.removeValue(forKey: id)
        logger.debug("Terminal \(id) removed")
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
}

/// 单个终端会话状态
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

    /// 近期输出缓存（最多 500 行，供 omaestri check 使用）
    private var outputBuffer: [String] = []
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
        outputBuffer.append(contentsOf: newLines)
        if outputBuffer.count > bufferMaxLines {
            outputBuffer = Array(outputBuffer.suffix(bufferMaxLines))
        }
        isIdle = false
        activityMonitor.recordOutput()
    }

    /// 获取最近 N 行输出
    func recentOutput(lines: Int = 20) -> String {
        Array(outputBuffer.suffix(lines)).joined(separator: "\n")
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
