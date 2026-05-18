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
        // TerminalProviderRegistry.register 不再覆盖此回调
        if let session = TerminalManager.shared.terminals[terminalId] {
            provider.onOutput = { text in
                Task { @MainActor in
                    session.recordOutput(text)
                }
                provider.recordOutputForScrollback(text)
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
        let cols = max(Int(nsView.frame.width / 8), 20)
        let rows = max(Int(nsView.frame.height / 16), 5)
        nsView.getTerminal().resize(cols: cols, rows: rows)
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

    /// 将已缓存的 terminalView 从当前父视图移除（供 Canvas 层重新 attach 前调用）
    @MainActor
    func detachTerminalView(for terminalId: UUID) {
        guard let view = providers[terminalId]?.terminalView else { return }
        view.removeFromSuperview()
    }
}
