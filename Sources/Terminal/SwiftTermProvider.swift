import Foundation
import OSLog
import SwiftTerm
import AppKit

/// 解析终端字体。"system" 标识符（对标 Maestri 默认值）映射到 monospacedSystemFont，
/// 其他值按 PostScript 字体名查找，找不到时 fallback 到 monospacedSystemFont。
func resolveTerminalFont(family: String, size: CGFloat) -> NSFont {
    if family == "system" || family.isEmpty {
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
    return NSFont(name: family, size: size)
        ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
}

/// SwiftTerm PTY 适配层 — 只负责 PTY 进程管理
/// - 通过子类化 LocalProcessTerminalView（OmLocalProcessTerminalView）的 dataReceived 检测输出
/// - shellReadyCallback：shell 就绪（100ms 静默）后触发一次
@MainActor
final class SwiftTermProvider: NSObject {
    private let logger = Logger.make(category: "SwiftTermProvider")

    // MARK: - 基础属性

    let terminalId: UUID
    let command: String
    let workingDirectory: String

    private(set) var terminalView: LocalProcessTerminalView?
    private(set) var isRunning: Bool = false

    // MARK: - 回调（外部设置，不由 SwiftTerm 自动触发）

    var onDataReceived: ((String) -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onBell: (() -> Void)?
    var onProcessExit: ((Int32?) -> Void)?

    /// shell 就绪后触发一次（300ms 静默检测）
    var shellReadyCallback: (() -> Void)?

    // MARK: - 配置

    var serverPort: UInt16 {
        get { _serverPort > 0 ? _serverPort : InterAgentServer.shared.port }
        set { _serverPort = newValue }
    }
    private var _serverPort: UInt16 = 0

    var workspaceId: UUID?
    var preferredFont: NSFont?
    var metalRendererEnabled: Bool = false

    /// cd + 自定义命令，由 start() 注入，shell 就绪后统一发送
    var pendingStartupCommands: [String] = []

    // startProcess 参数暂存：start() 创建视图后不立即启动进程，
    // 等 MaestroTerminalView.layout() 首次确定正确 bounds 后再由 firePendingStart() 触发。
    private struct PendingStart {
        let executable: String
        let args: [String]
        let environment: [String]
        let execName: String
        let currentDirectory: String?
    }
    private var pendingStart: PendingStart?

    // MARK: - Shell 就绪检测（内部）

    private var lastOutputTime: ContinuousClock.Instant = .now
    private var shellReadyScheduled = false
    private(set) var shellReadyCalled = false

    // MARK: - Scrollback

    private let scrollbackStore = ScrollbackStore()
    private var scrollbackDebounceTask: Task<Void, Never>?

    // MARK: - Init

    init(terminalId: UUID, command: String, workingDirectory: String) {
        self.terminalId = terminalId
        self.command = command
        self.workingDirectory = workingDirectory
    }

    // MARK: - 启动

    @discardableResult
    func start(in frame: NSRect) -> LocalProcessTerminalView {
        // 重置 shell 就绪状态，确保每次 start() 都能正确触发就绪检测流程。
        shellReadyCalled = false
        shellReadyScheduled = false

        let effectiveFrame = frame == .zero
            ? NSRect(x: 0, y: 0, width: 600, height: 400)
            : frame
        let view = OmLocalProcessTerminalView(frame: effectiveFrame)
        view.processDelegate = self

        // 通过子类回调获取 PTY 输出（不覆盖 terminalDelegate，保持 send 链路完整）
        view.onDataReceived = { [weak self] text in
            Task { @MainActor in self?.handleDataReceived(text) }
        }

        let prefs = (try? PersistenceManager.shared.loadPreferences()) ?? Preferences()
        applyThemeWithPrefs(to: view, prefs: prefs)
        applyFontWithPrefs(to: view, prefs: prefs)

        terminalView = view
        // isRunning 延迟到 firePendingStart() 实际启动进程后再设置

        enableMetalIfNeeded(view: view, metalEnabled: prefs.metalRendererEnabled)

        // 构建环境变量
        var env = ProcessInfo.processInfo.environment
        env["MAESTRI_TERMINAL_ID"] = terminalId.uuidString
        env["OMAESTRI_TERMINAL_ID"] = terminalId.uuidString
        if let socketPath = InterAgentServer.shared.currentSocketPath {
            env["MAESTRI_SOCKET"] = socketPath
        }
        env["TERM"] = "xterm-256color"
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let extraPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/.nvm/versions/node/current/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ].filter { FileManager.default.fileExists(atPath: $0) }
        if let resourcePath = Bundle.main.resourcePath {
            env["MAESTRI_CLI"] = "\(resourcePath)/omaestri"
            env["PATH"] = ([resourcePath] + extraPaths + [existingPath]).joined(separator: ":")
        } else {
            env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
        }

        let args: [String]
        let execName: String
        if command.isEmpty || command == "zsh" || command.hasSuffix("/zsh") {
            args = ["/bin/zsh", "--login"]
            execName = "zsh"
        } else if command == "bash" || command.hasSuffix("/bash") {
            args = ["/bin/bash", "--login"]
            execName = "bash"
        } else {
            // 非 shell 命令（如 claude, codex 等）：始终在 login shell 中运行。
            // 这样命令退出后 shell 仍然存活，用户回到 prompt 可继续交互。
            // 对标 Maestri 行为：终端节点是持久 shell session，agent 命令在其中运行。
            args = ["/bin/zsh", "--login"]
            execName = "zsh"
            pendingStartupCommands.append(command)
        }

        // 通过 startProcess(currentDirectory:) 原生设置工作目录，
        // 避免 shell 中出现可见的 cd 命令（PTY 子进程直接在目标目录启动）
        let startDir: String? = (!workingDirectory.isEmpty && FileManager.default.fileExists(atPath: workingDirectory))
            ? workingDirectory : nil

        // 增大 scrollback buffer（默认 500 行太小，长会话 resize 时会截断历史）
        view.getTerminal().changeScrollback(10000)

        // 暂存启动参数，等 MaestroTerminalView.layout() 首次完成后再调用 startProcess。
        // 这样 zsh 启动时拿到的是正确的内容区尺寸（不是 fallback 的 600x400），
        // terminal.cols 从一开始就基于真实 frame 计算，避免光标水平偏移。
        pendingStart = PendingStart(
            executable: args[0],
            args: Array(args.dropFirst()),
            environment: env.map { "\($0.key)=\($0.value)" },
            execName: execName,
            currentDirectory: startDir
        )
        logger.debug("PTY view ready (pending layout): \(self.command) in \(self.workingDirectory), terminalId=\(self.terminalId.uuidString.prefix(8))")

        return view
    }

    /// 由 MaestroTerminalView.layout() 在首次确定正确 bounds 后调用，触发真正的 PTY 启动。
    func firePendingStart() {
        guard let ps = pendingStart else { return }
        pendingStart = nil
        guard let view = terminalView else { return }
        isRunning = true
        view.startProcess(
            executable: ps.executable,
            args: ps.args,
            environment: ps.environment,
            execName: ps.execName,
            currentDirectory: ps.currentDirectory
        )
        logger.debug("PTY started (after layout): \(self.command) in \(self.workingDirectory), terminalId=\(self.terminalId.uuidString.prefix(8))")
    }

    // MARK: - Shell 就绪检测

    /// 收到 PTY 输出后的统一处理入口（由 OmLocalProcessTerminalView.dataReceived 回调触发）
    private func handleDataReceived(_ text: String) {
        // 转发到外部回调（session.recordOutput 等）
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onDataReceived?(text)
            recordOutputForScrollback(text)
        }
        // Shell 就绪检测（100ms 静默即认为就绪，对标 Maestri 快速启动）
        lastOutputTime = .now
        guard !shellReadyCalled, !shellReadyScheduled else { return }
        guard !pendingStartupCommands.isEmpty || shellReadyCallback != nil else {
            shellReadyCalled = true
            return
        }
        shellReadyScheduled = true
        Task { @MainActor [weak self] in
            // 快速检测：100ms 间隔轮询，最多等待 3s
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !self.shellReadyCalled else { return }
                if ContinuousClock.now - self.lastOutputTime >= .milliseconds(80) {
                    self.fireShellReady()
                    return
                }
            }
            self?.fireShellReady()
        }
    }

    private func fireShellReady() {
        guard !shellReadyCalled else { return }
        shellReadyCalled = true
        if !pendingStartupCommands.isEmpty {
            let combined = pendingStartupCommands.joined(separator: " && ")
            pendingStartupCommands.removeAll()
            write(combined + "\n")
        }
        shellReadyCallback?()
        shellReadyCallback = nil
    }

    /// 外部强制标记 shell 已就绪（供 TerminalManager 超时路径调用）
    /// 防止 processTerminated 在超时后再次触发 drainNext
    func forceMarkShellReady() {
        shellReadyCalled = true
        shellReadyCallback = nil
        pendingStartupCommands.removeAll()
    }

    // MARK: - PTY 写入

    func write(_ text: String) {
        guard let view = terminalView, isRunning else { return }
        view.send(txt: text)
    }

    func writeLine(_ text: String) {
        write(text + "\n")
    }

    // MARK: - 停止

    func stop() {
        guard isRunning else { return }
        isRunning = false
        // 退出前做最后一次 scrollback 快照（必须在 terminalView 置 nil 之前）
        if let view = terminalView, let wsId = workspaceId {
            let terminal = view.getTerminal()
            let data = terminal.getBufferAsData()
            if !data.isEmpty {
                let fullText = String(decoding: data, as: UTF8.self)
                var lines = fullText.components(separatedBy: "\n")
                while let last = lines.last, last.isEmpty { lines.removeLast() }
                if !lines.isEmpty {
                    let maxLines = 5000
                    let toKeep = lines.count > maxLines ? Array(lines.suffix(maxLines)) : lines
                    let entries = toKeep.map { ScrollbackEntry(attributes: [], text: $0) }
                    Task.detached { [scrollbackStore, terminalId] in
                        try? await scrollbackStore.save(entries: entries, terminalId: terminalId, workspaceId: wsId)
                    }
                }
            }
        }
        terminalView?.terminate()
        terminalView = nil
    }

    // MARK: - 滚动锁定

    private(set) var isAutoScrollLocked: Bool = false

    func setAutoScrollLocked(_ locked: Bool) {
        isAutoScrollLocked = locked
        logger.debug("Terminal \(self.terminalId.uuidString.prefix(8)) autoScrollLocked=\(locked)")
    }

    // MARK: - 进程重启

    func restartProcess(command: String, workingDirectory: String) {
        write("exit\n")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            let escapedPath = workingDirectory.replacingOccurrences(of: "'", with: "'\\''")
            let launchCmd = command.isEmpty ? "zsh --login" : command
            self.write("cd '\(escapedPath)' && \(launchCmd)\n")
            self.logger.debug("Terminal \(self.terminalId.uuidString.prefix(8)) restarted in \(workingDirectory)")
        }
    }

    // MARK: - Metal 渲染器

    private func enableMetalIfNeeded(view: LocalProcessTerminalView, metalEnabled: Bool) {
        guard metalEnabled else { return }
        Task { @MainActor in
            do {
                try view.setUseMetal(true)
                self.logger.debug("Metal renderer enabled for terminal \(self.terminalId.uuidString.prefix(8))")
            } catch {
                self.logger.warning("Failed to enable Metal renderer: \(error.localizedDescription)")
            }
        }
    }

    func applyMetalRenderer(enabled: Bool) {
        guard let view = terminalView else { return }
        do {
            try view.setUseMetal(enabled)
            logger.debug("Metal renderer \(enabled ? "enabled" : "disabled") for terminal \(self.terminalId.uuidString.prefix(8))")
        } catch {
            logger.warning("Failed to toggle Metal renderer: \(error.localizedDescription)")
        }
    }

    // MARK: - 主题应用

    private func applyThemeWithPrefs(to view: LocalProcessTerminalView, prefs: Preferences) {
        let themeId = TerminalThemeRegistry.resolveThemeId(from: prefs.terminalTheme)
        TerminalThemeRegistry.shared.apply(themeId: themeId, to: view)
    }

    func applyCurrentTheme(to view: LocalProcessTerminalView) {
        let preference: String
        if let prefs = try? PersistenceManager.shared.loadPreferences() {
            preference = prefs.terminalTheme
        } else {
            preference = "dark"
        }
        let themeId = TerminalThemeRegistry.resolveThemeId(from: preference)
        TerminalThemeRegistry.shared.apply(themeId: themeId, to: view)
    }

    func applyTheme(_ themeId: String) {
        guard let view = terminalView else { return }
        TerminalThemeRegistry.shared.apply(themeId: themeId, to: view)
    }

    // MARK: - 字体应用

    private func applyFontWithPrefs(to view: LocalProcessTerminalView, prefs: Preferences) {
        view.font = resolveTerminalFont(family: prefs.terminalFontFamily, size: prefs.terminalFontSize)
    }

    func applyCurrentFont(to view: LocalProcessTerminalView) {
        if let prefs = try? PersistenceManager.shared.loadPreferences() {
            view.font = resolveTerminalFont(family: prefs.terminalFontFamily, size: prefs.terminalFontSize)
            view.setFrameSize(view.frame.size)
        }
    }

    func applyFont(family: String, size: CGFloat) {
        guard let view = terminalView else { return }
        view.font = resolveTerminalFont(family: family, size: size)
        view.setFrameSize(view.frame.size)
        logger.debug("Font updated to \(family) \(size)pt for terminal \(self.terminalId.uuidString.prefix(8))")
    }

    // MARK: - Scrollback 恢复（启动时 feed 历史到终端视图）

    /// 在 PTY startProcess 前将保存的 scrollback 数据 feed 到终端视图。
    /// resize 时 reflow 可能导致显示错位，但磁盘快照通过 snapshotScrollbackBeforeResize
    /// 保护，不会丢失历史。
    private func feedScrollbackBeforeStart(view: LocalProcessTerminalView, workspaceId: UUID) {
        let store = ScrollbackStore()
        guard let entries = try? store.load(terminalId: terminalId, workspaceId: workspaceId),
              !entries.isEmpty else { return }

        // 检测旧格式数据（含光标移动等 CSI 序列）：如果发现则跳过恢复
        let sampleEntries = entries.suffix(min(20, entries.count))
        let hasCursorMovement = sampleEntries.contains { entry in
            entry.text.range(of: "\u{1b}\\[[0-9;]*[ABCDHJKf]", options: .regularExpression) != nil
        }
        if hasCursorMovement {
            logger.debug("Scrollback contains legacy PTY data with cursor sequences, skipping restore for terminal \(self.terminalId.uuidString.prefix(8))")
            return
        }

        // 取最后 2000 行
        let maxRestoreLines = 2000
        let toRestore = entries.count > maxRestoreLines
            ? Array(entries.suffix(maxRestoreLines))
            : entries

        let text = toRestore.map { $0.text }.joined(separator: "\r\n")
        guard !text.isEmpty else { return }

        view.feed(text: text + "\r\n")
        logger.debug("Scrollback restored: \(toRestore.count) lines for terminal \(self.terminalId.uuidString.prefix(8))")
    }

    // MARK: - Scrollback 持久化（从 terminal buffer 提取已渲染的屏幕行）

    /// 从 SwiftTerm terminal buffer 提取所有行（scrollback + 可视区），存为 JSONL。
    /// 每行是 translateToString 的纯文本输出，不含光标移动/清屏等控制序列。
    /// 恢复时可安全 feed 到任意尺寸的终端而不会错位。
    func recordOutputForScrollback(_ text: String) {
        // resize 冻结期内跳过，防止 reflow 破坏的 buffer 被持久化
        guard !scrollbackFrozen else { return }
        // 标记有新数据到达，触发 debounce 快照保存
        scrollbackDirty = true
        if scrollbackDebounceTask == nil {
            scrollbackDebounceTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                await self?.flushScrollback()
                self?.scrollbackDebounceTask = nil
            }
        }
    }

    /// 是否有新数据需要快照
    private var scrollbackDirty = false

    /// resize 后短暂冻结 scrollback 写入，防止 reflow 后的破坏 buffer 覆盖磁盘快照
    private var scrollbackFrozen = false

    /// 从 terminal buffer 提取所有行并持久化
    func flushScrollback() async {
        guard scrollbackDirty, let wsId = workspaceId, let view = terminalView else { return }
        scrollbackDirty = false

        // 通过 SwiftTerm public API 获取整个 buffer 内容（含 scrollback + 可视区域）
        // getBufferAsData 内部遍历 buffer.lines，对每行调用 translateToString(trimRight: true)
        // 结果是纯文本（无光标移动序列），每行以 \n 分隔
        let terminal = view.getTerminal()
        let data = terminal.getBufferAsData()
        guard !data.isEmpty else { return }

        let fullText = String(decoding: data, as: UTF8.self)
        var lines = fullText.components(separatedBy: "\n")

        // 去掉尾部空行
        while let last = lines.last, last.isEmpty {
            lines.removeLast()
        }

        guard !lines.isEmpty else { return }

        // 转为 ScrollbackEntry 并持久化
        let maxLines = 5000
        let toKeep = lines.count > maxLines ? Array(lines.suffix(maxLines)) : lines
        let entries = toKeep.map { ScrollbackEntry(attributes: [], text: $0) }
        try? await scrollbackStore.save(entries: entries, terminalId: terminalId, workspaceId: wsId)
    }

    func flushScrollbackNow() {
        Task { await flushScrollback() }
    }

    /// resize 前同步调用：立即把当前 buffer 内容写入磁盘，不走 debounce。
    /// 必须在 terminalView.frame 变化（触发 SwiftTerm reflow）之前调用，
    /// 否则 reflow 会破坏 buffer 内容，导致历史记录丢失。
    func snapshotScrollbackBeforeResize() {
        guard let wsId = workspaceId, let view = terminalView else { return }
        let terminal = view.getTerminal()
        let data = terminal.getBufferAsData()
        guard !data.isEmpty else { return }

        let fullText = String(decoding: data, as: UTF8.self)
        var lines = fullText.components(separatedBy: "\n")
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        guard !lines.isEmpty else { return }

        let maxLines = 5000
        let toKeep = lines.count > maxLines ? Array(lines.suffix(maxLines)) : lines
        let entries = toKeep.map { ScrollbackEntry(attributes: [], text: $0) }

        // 取消正在进行的 debounce task，避免 resize 后的破坏 buffer 覆盖这次快照
        scrollbackDebounceTask?.cancel()
        scrollbackDebounceTask = nil
        scrollbackDirty = false

        // 冻结 scrollback 写入 2 秒：resize 完成后 PTY 可能立即有输出（SIGWINCH 响应），
        // 此时 buffer 已被 reflow 破坏，不能让这些输出触发新的 flush
        scrollbackFrozen = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.scrollbackFrozen = false
        }

        let store = scrollbackStore
        let termId = terminalId
        Task.detached(priority: .utility) {
            try? await store.save(entries: entries, terminalId: termId, workspaceId: wsId)
        }
        logger.debug("Pre-resize snapshot: \(toKeep.count) lines for terminal \(self.terminalId.uuidString.prefix(8))")
    }
}


// MARK: - LocalProcessTerminalViewDelegate

extension SwiftTermProvider: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        let tid = terminalId
        Task { @MainActor in
            Logger.make(category: "SwiftTermProvider").debug("Terminal \(tid.uuidString.prefix(8)) resized: \(newCols)x\(newRows)")
        }
    }

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in
            self.onTitleChange?(title)
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        let tid = terminalId
        Task { @MainActor in
            TerminalManager.shared.terminals[tid]?.updateCurrentDirectory(directory)
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.isRunning = false
            await self.flushScrollback()
            self.onProcessExit?(exitCode)
            Logger.make(category: "SwiftTermProvider").info("Terminal \(self.terminalId.uuidString.prefix(8)) terminated with code \(exitCode ?? -1)")
            // PTY 退出时若 shell 从未就绪（如命令不存在），强制触发以推进串行启动队列
            if !self.shellReadyCalled {
                self.fireShellReady()
            }
        }
    }
}

// MARK: - OmLocalProcessTerminalView（子类化以获取 PTY 输出，不破坏 send 链路）

/// 子类化 LocalProcessTerminalView，覆盖 dataReceived 获取 PTY 输出文本。
/// 保持 terminalDelegate = self 不变（LocalProcessTerminalView 在 setup 中设置），
/// 从而 send(source:data:) 仍然由 LocalProcessTerminalView 自身处理 → process.send。
final class OmLocalProcessTerminalView: LocalProcessTerminalView {
    /// PTY 有新输出时回调（原始文本）
    var onDataReceived: ((String) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        if let text = String(bytes: slice, encoding: .utf8) {
            onDataReceived?(text)
        }
    }
}
