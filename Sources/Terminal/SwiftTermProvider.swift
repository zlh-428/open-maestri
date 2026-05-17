import Foundation
import OSLog
import SwiftTerm

/// SwiftTerm PTY 适配层
/// - 为每个 Terminal 节点管理一个 LocalProcessTerminalView
/// - 实现 VT100/xterm-256color 完整支持
/// - 启动时注入 OMAESTRI_* 环境变量，使 CLI 可用
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
        view.configureNativeColors()
        terminalView = view
        isRunning = true

        // 构建环境变量：保留系统环境 + 注入 OMAESTRI_* + 扩展 PATH
        var env = ProcessInfo.processInfo.environment
        env["OMAESTRI_TERMINAL_ID"] = terminalId.uuidString
        env["OMAESTRI_HOST"] = "\(Constants.interAgentServerHost):\(serverPort)"
        env["OMAESTRI_CLI"] = ""
        env["TERM"] = "xterm-256color"
        // 确保 PATH 包含常用工具目录（解决 "claude" 等命令无法被 execve 找到的问题）
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let extraPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/.nvm/versions/node/current/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ].filter { FileManager.default.fileExists(atPath: $0) }
        env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")

        let args: [String]
        if command.isEmpty || command == "zsh" || command.hasSuffix("/zsh") {
            args = ["/bin/zsh", "--login"]
        } else if command == "bash" || command.hasSuffix("/bash") {
            args = ["/bin/bash", "--login"]
        } else {
            // 对非 shell 命令尝试用 which 解析完整路径
            let resolved = resolveCommandPath(command, env: env)
            args = [resolved]
        }

        view.startProcess(
            executable: args[0],
            args: Array(args.dropFirst()),
            environment: env.map { "\($0.key)=\($0.value)" },
            execName: command.isEmpty ? "zsh" : command
        )
        logger.debug("PTY started: \(self.command) in \(self.workingDirectory), terminalId=\(self.terminalId.uuidString.prefix(8))")

        // SwiftTerm 的 startProcess 不直接支持 cwd，通过 cd 命令切换到工作目录
        if !workingDirectory.isEmpty && FileManager.default.fileExists(atPath: workingDirectory) {
            let escapedPath = workingDirectory.replacingOccurrences(of: "'", with: "'\\''")
            // 延迟 0.3s 等 shell 初始化完成后再 cd
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.write("cd '\(escapedPath)'\n")
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

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

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
