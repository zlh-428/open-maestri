import Foundation
import OSLog
import SwiftTerm
import AppKit

/// SwiftTerm PTY 适配层 — 只负责 PTY 进程管理
/// - 通过子类化 LocalProcessTerminalView（OmLocalProcessTerminalView）的 dataReceived 检测输出
/// - shellReadyCallback：shell 就绪（300ms 静默）后触发一次
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

    // MARK: - Shell 就绪检测（内部）

    private var lastOutputTime: ContinuousClock.Instant = .now
    private var shellReadyScheduled = false
    private(set) var shellReadyCalled = false

    // MARK: - Scrollback

    private let scrollbackStore = ScrollbackStore()
    private var pendingScrollback: [ScrollbackEntry] = []
    private let scrollbackFlushThreshold = 50
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
        isRunning = true

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

        view.startProcess(
            executable: args[0],
            args: Array(args.dropFirst()),
            environment: env.map { "\($0.key)=\($0.value)" },
            execName: execName,
            currentDirectory: startDir
        )
        logger.debug("PTY started: \(self.command) in \(self.workingDirectory), terminalId=\(self.terminalId.uuidString.prefix(8))")

        return view
    }

    // MARK: - Shell 就绪检测

    /// 收到 PTY 输出后的统一处理入口（由 OmLocalProcessTerminalView.dataReceived 回调触发）
    private func handleDataReceived(_ text: String) {
        // 转发到外部回调（session.recordOutput 等）
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onDataReceived?(text)
            recordOutputForScrollback(text)
        }
        // Shell 就绪检测
        lastOutputTime = .now
        guard !shellReadyCalled, !shellReadyScheduled else { return }
        guard !pendingStartupCommands.isEmpty || shellReadyCallback != nil else {
            shellReadyCalled = true
            return
        }
        shellReadyScheduled = true
        Task { @MainActor [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !self.shellReadyCalled else { return }
                if ContinuousClock.now - self.lastOutputTime >= .milliseconds(280) {
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
        let font = NSFont(name: prefs.terminalFontFamily, size: prefs.terminalFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: prefs.terminalFontSize, weight: .regular)
        view.font = font
    }

    func applyCurrentFont(to view: LocalProcessTerminalView) {
        if let prefs = try? PersistenceManager.shared.loadPreferences() {
            let font = NSFont(name: prefs.terminalFontFamily, size: prefs.terminalFontSize)
                ?? NSFont.monospacedSystemFont(ofSize: prefs.terminalFontSize, weight: .regular)
            view.font = font
        }
    }

    func applyFont(family: String, size: CGFloat) {
        guard let view = terminalView else { return }
        let font = NSFont(name: family, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        view.font = font
        logger.debug("Font updated to \(family) \(size)pt for terminal \(self.terminalId.uuidString.prefix(8))")
    }

    // MARK: - Scrollback 持久化

    func recordOutputForScrollback(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        for line in lines where !line.isEmpty {
            pendingScrollback.append(ScrollbackEntry(attributes: [], text: line))
        }
        if pendingScrollback.count >= scrollbackFlushThreshold {
            scrollbackDebounceTask?.cancel()
            scrollbackDebounceTask = nil
            Task { await flushScrollback() }
        } else {
            if scrollbackDebounceTask == nil {
                scrollbackDebounceTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    await self?.flushScrollback()
                    self?.scrollbackDebounceTask = nil
                }
            }
        }
    }

    func flushScrollback() async {
        guard !pendingScrollback.isEmpty, let wsId = workspaceId else { return }
        let toFlush = pendingScrollback
        pendingScrollback.removeAll()
        try? await scrollbackStore.append(lines: toFlush, terminalId: terminalId, workspaceId: wsId)
    }

    func flushScrollbackNow() {
        Task { await flushScrollback() }
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
        // 先调用 super 让 SwiftTerm 正常 feed 数据到终端 buffer
        super.dataReceived(slice: slice)
        // 将原始字节转为 UTF-8 文本，回调给 provider
        if let text = String(bytes: slice, encoding: .utf8) {
            onDataReceived?(text)
        }
    }
}
