import AppKit
import OSLog
import SwiftTerm

/// NSView 直接子类，对标 Maestri 的 MaestroTerminalView。
/// canvas 的 layout() 直接设置其 frame，SwiftTerm 内部 setFrameSize → processSizeChange
/// 自动处理 resize + SIGWINCH，完全绕开 SwiftUI diff。
@MainActor
final class MaestroTerminalView: NSView {
    private let logger = Logger.make(category: "MaestroTerminalView")
    private(set) var terminalView: LocalProcessTerminalView?
    let terminalId: UUID
    private(set) var isRunning: Bool = false
    var canvasZoom: CGFloat = 1.0
    var onDataReceived: ((String) -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onProcessExit: ((Int32?) -> Void)?

    init(terminalId: UUID, frame: NSRect = .zero) {
        self.terminalId = terminalId
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }
}

// MARK: - attach / detach

extension MaestroTerminalView {
    /// 首次调用启动 PTY 并 addSubview；再次调用仅 re-attach（不重启 PTY）。
    func attach(provider: SwiftTermProvider) {
        if let existing = provider.terminalView {
            if existing.superview != self {
                existing.removeFromSuperview()
                existing.frame = bounds
                existing.autoresizingMask = [.width, .height]
                addSubview(existing)
            }
            terminalView = existing
            isRunning = provider.isRunning
            applyThemeAndFont(to: existing, provider: provider)
            return
        }

        let tv = provider.start(in: bounds)
        tv.autoresizingMask = [.width, .height]
        addSubview(tv)
        terminalView = tv
        isRunning = true

        provider.onTitleChange = { [weak self] title in
            self?.onTitleChange?(title)
        }
        logger.debug("Attached terminal \(self.terminalId.uuidString.prefix(8))")
    }

    /// removeFromSuperview，不停止 PTY（工作区切换用）。
    func detach() {
        terminalView?.removeFromSuperview()
        logger.debug("Detached terminal \(self.terminalId.uuidString.prefix(8))")
    }

    private func applyThemeAndFont(to tv: LocalProcessTerminalView, provider: SwiftTermProvider) {
        let prefs = (try? PersistenceManager.shared.loadPreferences()) ?? Preferences()
        let themeId = TerminalThemeRegistry.resolveThemeId(from: prefs.terminalTheme)
        TerminalThemeRegistry.shared.apply(themeId: themeId, to: tv)
        let font = NSFont(name: prefs.terminalFontFamily, size: prefs.terminalFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: prefs.terminalFontSize, weight: .regular)
        tv.font = font
    }
}

// MARK: - Layout

extension MaestroTerminalView {
    override func layout() {
        super.layout()
        // 同步子视图 frame；LocalProcessTerminalView 的 setFrameSize 会自动触发
        // processSizeChange → terminalDelegate.sizeChanged → SIGWINCH，无需手动 resize
        terminalView?.frame = bounds
    }
}

// MARK: - Scrollback（已禁用 feed 恢复）

extension MaestroTerminalView {
    /// Scrollback 恢复已禁用：将旧 PTY 输出（含 ANSI 转义）重新 feed 进 terminal buffer
    /// 会导致 resize 后行包裹错乱、光标位置偏移等渲染问题。
    /// 历史记录通过 TerminalSession.bulkLoadHistory 保留在内存中，
    /// 供 omaestri check 等 API 使用，但不再回显到终端界面。
    func loadScrollback(workspaceId: UUID) {
        // no-op: 不再将历史文本 feed 回终端视图
    }
}
