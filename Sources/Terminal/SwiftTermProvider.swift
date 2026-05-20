import Foundation
import OSLog
import SwiftTerm
import AppKit

/// SwiftTerm PTY 适配层
/// - 为每个 Terminal 节点管理一个 LocalProcessTerminalView
/// - 实现 VT100/xterm-256color 完整支持
/// - 启动时注入 MAESTRI_* 环境变量，使 CLI 可用
@MainActor
final class SwiftTermProvider: NSObject {
    private let logger = Logger.make(category: "SwiftTermProvider")

    let terminalId: UUID
    let workingDirectory: String
    let command: String

    /// InterAgentServer 端口；始终从 InterAgentServer.shared.port 读取最新值
    var serverPort: UInt16 {
        get { _serverPort > 0 ? _serverPort : InterAgentServer.shared.port }
        set { _serverPort = newValue }
    }
    private var _serverPort: UInt16 = 0
    /// 所属工作区 ID（用于 ScrollbackStore 路径）
    var workspaceId: UUID?

    private(set) var terminalView: LocalProcessTerminalView?
    var onOutput: ((String) -> Void)?
    var onTitleChange: ((String) -> Void)?
    private(set) var isRunning: Bool = false

    private let scrollbackStore = ScrollbackStore()
    private var pendingScrollback: [ScrollbackEntry] = []
    private let scrollbackFlushThreshold = 50
    /// 无法直接 execve 的命令（alias/函数等），shell 启动后延迟发送
    private var pendingCommand: String? = nil

    init(terminalId: UUID, command: String, workingDirectory: String) {
        self.terminalId = terminalId
        self.command = command
        self.workingDirectory = workingDirectory
    }

    // MARK: - 启动

    func start(in frame: NSRect) -> LocalProcessTerminalView {
        // 使用合理的默认尺寸避免 PTY cols/rows 为 0
        let effectiveFrame = frame == .zero
            ? NSRect(x: 0, y: 0, width: 600, height: 400)
            : frame
        let view = LocalProcessTerminalView(frame: effectiveFrame)
        view.processDelegate = self

        // 应用终端主题（替代简单的 configureNativeColors）
        applyCurrentTheme(to: view)
        // 应用终端字体
        applyCurrentFont(to: view)

        terminalView = view
        isRunning = true

        // 启用 Metal GPU 渲染器（如果偏好中开启）
        enableMetalIfNeeded(view: view)

        // 构建环境变量：保留系统环境 + 注入 MAESTRI_* + 扩展 PATH
        var env = ProcessInfo.processInfo.environment
        // Maestri 兼容变量
        env["MAESTRI_TERMINAL_ID"] = terminalId.uuidString
        env["OMAESTRI_TERMINAL_ID"] = terminalId.uuidString  // 向后兼容
        // Unix socket 路径
        if let socketPath = InterAgentServer.shared.currentSocketPath {
            env["MAESTRI_SOCKET"] = socketPath
        }
        env["TERM"] = "xterm-256color"
        // 确保 PATH 包含常用工具目录（解决 "claude" 等命令无法被 execve 找到的问题）
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let extraPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/.nvm/versions/node/current/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ].filter { FileManager.default.fileExists(atPath: $0) }
        // CLI 二进制路径 + PATH 注入（resourcePath 放最前面）
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
            // 先尝试在 PATH 里找到可执行文件
            let resolved = resolveCommandPath(command, env: env)
            if FileManager.default.isExecutableFile(atPath: resolved) {
                // 找到可执行文件，直接执行
                args = [resolved]
                execName = command
            } else {
                // 找不到可执行文件（可能是 alias、shell 函数、多词命令等）
                // 启动交互式 login shell，稍后通过 write() 发送命令字符串
                // 交互式 shell 会加载 .zshrc，alias 在其中定义，可以正常展开
                args = ["/bin/zsh", "--login"]
                execName = "zsh"
                pendingCommand = command
            }
        }

        view.startProcess(
            executable: args[0],
            args: Array(args.dropFirst()),
            environment: env.map { "\($0.key)=\($0.value)" },
            execName: execName
        )
        logger.debug("PTY started: \(self.command) in \(self.workingDirectory), terminalId=\(self.terminalId.uuidString.prefix(8))")

        // SwiftTerm 的 startProcess 不直接支持 cwd，通过 cd 命令切换到工作目录
        // 若有 pendingCommand（alias/函数），在 cd 之后再发送，确保 shell 已完全初始化
        let hasCd = !workingDirectory.isEmpty && FileManager.default.fileExists(atPath: workingDirectory)
        let pending = pendingCommand
        if hasCd {
            let escapedPath = workingDirectory.replacingOccurrences(of: "'", with: "'\\''")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.write("cd '\(escapedPath)'\n")
                if let cmd = pending {
                    // 额外延迟确保 cd 已执行
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.write("\(cmd)\n")
                    }
                }
            }
        } else if let cmd = pending {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.write("\(cmd)\n")
            }
        }
        return view
    }

    // MARK: - 命令路径解析

    private func resolveCommandPath(_ cmd: String, env: [String: String]) -> String {
        // 已是绝对路径
        if cmd.hasPrefix("/") { return cmd }
        // 通过 PATH 搜索
        let searchPaths = (env["PATH"] ?? "").components(separatedBy: ":")
        for dir in searchPaths {
            let full = "\(dir)/\(cmd)"
            if FileManager.default.isExecutableFile(atPath: full) { return full }
        }
        return cmd  // fallback：让系统自己查找
    }

    // MARK: - PTY 写入

    func write(_ text: String) {
        guard let view = terminalView, isRunning else { return }
        view.send(txt: text)
    }

    func writeLine(_ text: String) {
        write(text + "\n")
    }

    // MARK: - 滚动锁定

    /// 是否锁定自动滚动（⌘⇧B 切换）
    private(set) var isAutoScrollLocked: Bool = false

    /// 设置自动滚动锁定状态（由 CanvasViewportView 的 ⌘⇧B 处理器调用）
    func setAutoScrollLocked(_ locked: Bool) {
        isAutoScrollLocked = locked
        // LocalProcessTerminalView 暂无直接 API 控制 auto-scroll，
        // 此处通过 SwiftTerm 的 terminal.getTerminal().setAutoScroll 未来可接入；
        // 目前仅保存状态标记，节点视图负责显示指示器。
        logger.debug("Terminal \(self.terminalId.uuidString.prefix(8)) autoScrollLocked=\(locked)")
    }

    // MARK: - 进程重启（用于 Assign Role 后立即重启）

    /// 向当前 PTY 发送 `exit` 并在新目录重新启动进程
    /// - Parameters:
    ///   - command: 新命令（通常与当前相同）
    ///   - workingDirectory: 新工作目录（role 子目录或原始目录）
    func restartProcess(command: String, workingDirectory: String) {
        // 先发送 exit 终止当前进程
        write("exit\n")
        // 延迟 0.5s 等进程退出，然后重新 cd 到新目录并启动命令
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let escapedPath = workingDirectory.replacingOccurrences(of: "'", with: "'\\''")
            let launchCmd = command.isEmpty ? "zsh --login" : command
            self.write("cd '\(escapedPath)' && \(launchCmd)\n")
            self.logger.debug("Terminal \(self.terminalId.uuidString.prefix(8)) restarted in \(workingDirectory)")
        }
    }

    // MARK: - Metal 渲染器

    /// 根据偏好启用或禁用 Metal GPU 渲染
    private func enableMetalIfNeeded(view: LocalProcessTerminalView) {
        // 读取偏好：metalRendererEnabled
        // 注意：此处在启动时只调用一次，后续切换通过 applyMetalRenderer 实现
        Task { @MainActor in
            let enabled = self.resolveMetalPreference()
            if enabled {
                do {
                    try view.setUseMetal(true)
                    self.logger.debug("Metal renderer enabled for terminal \(self.terminalId.uuidString.prefix(8))")
                } catch {
                    self.logger.warning("Failed to enable Metal renderer: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 动态切换 Metal 渲染状态（设置变更时调用）
    func applyMetalRenderer(enabled: Bool) {
        guard let view = terminalView else { return }
        do {
            try view.setUseMetal(enabled)
            logger.debug("Metal renderer \(enabled ? "enabled" : "disabled") for terminal \(self.terminalId.uuidString.prefix(8))")
        } catch {
            logger.warning("Failed to toggle Metal renderer: \(error.localizedDescription)")
        }
    }

    private func resolveMetalPreference() -> Bool {
        // 从 PersistenceManager 读取偏好（避免循环依赖 AppState）
        if let prefs = try? PersistenceManager.shared.loadPreferences() {
            return prefs.metalRendererEnabled
        }
        return true // 默认启用
    }

    // MARK: - 主题应用

    /// 应用当前主题到终端视图
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

    /// 即时切换主题
    func applyTheme(_ themeId: String) {
        guard let view = terminalView else { return }
        TerminalThemeRegistry.shared.apply(themeId: themeId, to: view)
    }

    // MARK: - 字体应用

    /// 应用当前字体到终端视图
    func applyCurrentFont(to view: LocalProcessTerminalView) {
        if let prefs = try? PersistenceManager.shared.loadPreferences() {
            let font = NSFont(name: prefs.terminalFontFamily, size: prefs.terminalFontSize)
                ?? NSFont.monospacedSystemFont(ofSize: prefs.terminalFontSize, weight: .regular)
            view.font = font
        }
    }

    /// 即时更新字体（无需重启终端）
    func applyFont(family: String, size: CGFloat) {
        guard let view = terminalView else { return }
        let font = NSFont(name: family, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        view.font = font
        logger.debug("Font updated to \(family) \(size)pt for terminal \(self.terminalId.uuidString.prefix(8))")
    }

    // MARK: - 停止

    func stop() {
        isRunning = false
        terminalView = nil
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
            // 终止时 flush 剩余 scrollback
            await self.flushScrollback()
            Logger.make(category: "SwiftTermProvider").info("Terminal \(self.terminalId.uuidString.prefix(8)) terminated with code \(exitCode ?? -1)")
        }
    }

    // MARK: - Scrollback 持久化

    func recordOutputForScrollback(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        for line in lines where !line.isEmpty {
            pendingScrollback.append(ScrollbackEntry(attributes: [], text: line))
        }
        if pendingScrollback.count >= scrollbackFlushThreshold {
            Task { await flushScrollback() }
        }
    }

    private func flushScrollback() async {
        guard !pendingScrollback.isEmpty, let wsId = workspaceId else { return }
        let toFlush = pendingScrollback
        pendingScrollback.removeAll()
        try? await scrollbackStore.append(lines: toFlush, terminalId: terminalId, workspaceId: wsId)
    }
}
