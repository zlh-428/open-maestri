import SwiftUI
import AppKit
import SwiftTerm

/// SwiftTerm PTY 终端嵌入视图
struct TerminalEmbeddedView: NSViewRepresentable {
    let terminalId: UUID
    let command: String
    let workingDirectory: String
    var serverPort: UInt16 = 0
    var workspaceId: UUID?

    @MainActor
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        // 复用已有 provider（切换工作区后 Canvas 重建时不重启 PTY）
        if let existing = TerminalProviderRegistry.shared.provider(for: terminalId),
           let existingView = existing.terminalView {
            existing.terminalView?.removeFromSuperview()
            // 重新 attach 时同步最新主题和字体（preferences 可能在离开期间已变更）
            existing.applyCurrentTheme(to: existingView)
            existing.applyCurrentFont(to: existingView)
            return existingView
        }

        let provider = SwiftTermProvider(
            terminalId: terminalId,
            command: command,
            workingDirectory: workingDirectory
        )
        provider.serverPort = serverPort > 0 ? serverPort : InterAgentServer.shared.port
        provider.workspaceId = workspaceId

        // 使用 .zero，让父视图的 autoresizingMask 决定实际尺寸
        let view = provider.start(in: .zero)

        // 单一的输出链路：PTY 输出 → TerminalSession 缓存 + ScrollbackStore
        if let session = TerminalManager.shared.terminals[terminalId] {
            provider.onOutput = { [weak provider] text in
                // 首次输出表示 shell prompt 就绪，触发发送暂存的 cd/command
                provider?.handleFirstOutput()
                Task { @MainActor in
                    session.recordOutput(text)
                }
                provider?.recordOutputForScrollback(text)
            }
        }

        // 注册 provider 引用（仅用于 TerminalManager.write → PTY 写入路径）
        let tid = terminalId
        TerminalProviderRegistry.shared.register(terminalId: tid, provider: provider)

        return view
    }

    @MainActor
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // 根据实际视图尺寸更新 PTY 行列
        // 防抖：相同尺寸跳过 + 高频 resize 时通过 debounce 合并 SIGWINCH 信号
        let cols = max(Int(nsView.frame.width / 8), 20)
        let rows = max(Int(nsView.frame.height / 16), 5)
        let terminal = nsView.getTerminal()
        guard terminal.cols != cols || terminal.rows != rows else { return }
        // 使用延迟执行合并快速连续的 resize（如窗口拖拽），
        // 避免对 PTY 发送过多 SIGWINCH 导致子进程抖动
        TerminalResizeDebouncer.shared.scheduleResize(terminalId: terminalId, cols: cols, rows: rows, terminal: terminal)
    }

    @MainActor
    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: ()) {
        // 视图销毁时从注册表中移除，防止内存泄漏
    }
}

// MARK: - TerminalProviderRegistry

/// 全局注册表：terminalId → SwiftTermProvider
/// 职责：
///   1. 存储 provider 引用，供 TerminalManager.write 转发写入 PTY
///   2. 缓存 LocalProcessTerminalView，使其生命周期独立于 Canvas View 层级，
///      实现切换工作区时 PTY 进程不重置（复用已有 terminalView）
final class TerminalProviderRegistry {
    static let shared = TerminalProviderRegistry()
    private var providers: [UUID: SwiftTermProvider] = [:]
    private let lock = NSLock()
    private init() {}

    func register(terminalId: UUID, provider: SwiftTermProvider) {
        lock.lock(); defer { lock.unlock() }
        providers[terminalId] = provider
        // 将 TerminalManager.write 路径接通：TerminalSession.onOutput → PTY.write
        // 注意：仅在 session.onOutput 为 nil 时才设置，避免覆盖 makeNSView 中已设置的回调
        Task { @MainActor in
            if let session = TerminalManager.shared.terminals[terminalId],
               session.onOutput == nil {
                session.onOutput = { [weak provider] text in
                    provider?.write(text)
                }
            }
        }
    }

    func unregister(terminalId: UUID) {
        lock.lock(); defer { lock.unlock() }
        providers.removeValue(forKey: terminalId)
    }

    func provider(for terminalId: UUID) -> SwiftTermProvider? {
        lock.lock(); defer { lock.unlock() }
        return providers[terminalId]
    }

    func allProviders() -> [SwiftTermProvider] {
        lock.lock(); defer { lock.unlock() }
        return Array(providers.values)
    }

    /// 将已缓存的 terminalView 从当前父视图移除（供 Canvas 层重新 attach 前调用）
    @MainActor
    func detachTerminalView(for terminalId: UUID) {
        guard let view = providers[terminalId]?.terminalView else { return }
        view.removeFromSuperview()
    }

    /// 退出时终止所有 PTY 进程，避免僵尸进程（必须在主线程调用）
    @MainActor
    func terminateAll() {
        lock.lock(); defer { lock.unlock() }
        for (_, provider) in providers {
            provider.stop()
        }
        providers.removeAll()
    }
}

// MARK: - TerminalResizeDebouncer

/// PTY resize 防抖器：合并 100ms 内的多次 resize 调用为一次 SIGWINCH
/// 避免窗口拖拽时对 PTY 子进程发送过多信号导致抖动
@MainActor
final class TerminalResizeDebouncer {
    static let shared = TerminalResizeDebouncer()
    private var pendingTasks: [UUID: Task<Void, Never>] = [:]
    private init() {}

    /// 调度 resize（取消前一次未执行的 resize，延迟 100ms 执行）
    func scheduleResize(terminalId: UUID, cols: Int, rows: Int, terminal: Terminal) {
        pendingTasks[terminalId]?.cancel()
        pendingTasks[terminalId] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            terminal.resize(cols: cols, rows: rows)
            self?.pendingTasks.removeValue(forKey: terminalId)
        }
    }
}
