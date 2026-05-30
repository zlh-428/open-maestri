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

    /// resize 防抖：暂存目标 bounds，200ms 静默后才真正更新 tv.frame
    private var pendingBounds: CGRect = .zero
    private var resizeDebounceTask: Task<Void, Never>?
    /// true = terminalView 首次出现在 layout 中，跳过防抖直接同步
    private var isInitialLayout: Bool = true

    /// 画布缩放期间冻结 layout，防止 scaleEffect 的 CALayer transform 变化
    /// 触发 Metal drawable 重建导致终端内容闪烁。
    /// 冻结期间 layout() 跳过所有 terminalView.frame 修改；
    /// unfreezeAfterZoom() 解冻后立即同步一次 frame。
    private(set) var isFrozenForZoom: Bool = false

    init(terminalId: UUID, frame: NSRect = .zero) {
        self.terminalId = terminalId
        super.init(frame: frame)
        wantsLayer = true
        updateBackgroundFromTheme()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }
}

// MARK: - attach / detach

extension MaestroTerminalView {
    /// 首次调用启动 PTY 并 addSubview；再次调用仅 re-attach（不重启 PTY）。
    func attach(provider: SwiftTermProvider) {
        if let existing = provider.terminalView {
            if existing.superview != self {
                // re-attach / restart：先移除旧的 terminalView（若有），再挂入新的
                let isRestart = terminalView != nil && terminalView !== existing
                if let old = terminalView, old !== existing {
                    old.removeFromSuperview()
                }
                layer?.backgroundColor = nil
                existing.removeFromSuperview()
                existing.frame = bounds
                existing.autoresizingMask = [.width, .height]
                addSubview(existing)
                // 重启场景：新 terminalView 需要通过 layout() 触发 firePendingStart()
                if isRestart { isInitialLayout = true }
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
        isRunning = false  // PTY 在 firePendingStart() 之后才真正启动

        provider.onTitleChange = { [weak self] title in
            self?.onTitleChange?(title)
        }
        logger.debug("Attached terminal \(self.terminalId.uuidString.prefix(8))")
    }

    /// removeFromSuperview，不停止 PTY（工作区切换用）。
    func detach() {
        terminalView?.removeFromSuperview()
        // 不重置 isInitialLayout：re-attach 时 terminalView 已有正确 frame，
        // 不需要再走首次 layout 的 firePendingStart 路径，避免不必要的 frame 重设。
        logger.debug("Detached terminal \(self.terminalId.uuidString.prefix(8))")
    }

    private func applyThemeAndFont(to tv: LocalProcessTerminalView, provider: SwiftTermProvider) {
        let prefs = (try? PersistenceManager.shared.loadPreferences()) ?? Preferences()
        let themeId = TerminalThemeRegistry.resolveThemeId(from: prefs.terminalTheme)
        TerminalThemeRegistry.shared.apply(themeId: themeId, to: tv)
        let font = NSFont(name: prefs.terminalFontFamily, size: prefs.terminalFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: prefs.terminalFontSize, weight: .regular)
        tv.font = font
        // resetFont() computes cols from frame.width without subtracting scrollerWidth;
        // re-trigger setFrameSize so processSizeChange corrects cols and cursor position.
        tv.setFrameSize(tv.frame.size)
        // attach 完成后清除占位背景，避免遮住 SwiftTerm 自己的 layer
        layer?.backgroundColor = nil
    }

    /// 用当前主题的背景色填充 layer，作为 PTY attach 前的占位色防止闪烁。
    /// 仅在 provider 尚未就绪（首次创建）时调用，re-attach 场景跳过。
    func updateBackgroundFromTheme() {
        let prefs = (try? PersistenceManager.shared.loadPreferences()) ?? Preferences()
        let themeId = TerminalThemeRegistry.resolveThemeId(from: prefs.terminalTheme)
        if let theme = TerminalThemeRegistry.shared.theme(for: themeId),
           let color = NSColor(hex: theme.background) {
            layer?.backgroundColor = color.cgColor
        } else {
            layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        }
    }
}

// MARK: - Layout

extension MaestroTerminalView {
    override func layout() {
        super.layout()
        guard let tv = terminalView else {
            isInitialLayout = true
            return
        }

        let newBounds = bounds

        // 首次 layout（attach 后第一次拿到真实尺寸）：优先于尺寸相等检查，
        // 确保 firePendingStart() 不被 "size == .zero 相等" 的情况跳过。
        // bounds == .zero 说明视图尚未布局完成，跳过以免 PTY 以零尺寸启动。
        if isInitialLayout {
            guard newBounds.size != .zero else { return }
            isInitialLayout = false
            tv.frame = newBounds
            // PTY 启动延迟到此处，确保 terminal.cols 基于真实 frame 计算
            TerminalManager.shared.providers[terminalId]?.firePendingStart()
            return
        }

        // bounds 没变，只同步 origin（平移画布等场景）
        if tv.frame.size == newBounds.size {
            tv.frame = newBounds
            return
        }

        // 画布缩放期间：冻结 terminalView.frame，让 scaleEffect 做纯视觉拉伸。
        // Metal layer 不感知 bounds 变化，不触发 drawable 重建，消除闪烁。
        // unfreezeAfterZoom() 会在缩放结束后同步一次正确 frame。
        if isFrozenForZoom {
            pendingBounds = newBounds
            return
        }

        // bounds 正在变化（resize 拖拽中）：使用防抖，避免每帧触发 SwiftTerm reflow。
        // 先把终端子视图锁定在旧尺寸（内容稳定不闪烁），200ms 静默后才真正 resize。
        pendingBounds = newBounds
        resizeDebounceTask?.cancel()
        resizeDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            self.commitResize()
        }
    }

    private func commitResize() {
        guard let tv = terminalView, tv.frame.size != pendingBounds.size else {
            terminalView?.frame = pendingBounds
            return
        }
        // resize 真正落地前先快照 scrollback，防止 reflow 破坏 buffer
        TerminalManager.shared.providers[terminalId]?.snapshotScrollbackBeforeResize()
        tv.frame = pendingBounds
    }

    // MARK: - 缩放冻结 / 解冻

    /// 画布捏合缩放开始时调用：冻结 terminalView frame，阻止 Metal drawable 重建。
    func freezeForZoom() {
        guard !isFrozenForZoom else { return }
        isFrozenForZoom = true
        // 取消 resize 防抖任务，缩放结束后由 unfreezeAfterZoom 统一处理
        resizeDebounceTask?.cancel()
        resizeDebounceTask = nil
    }

    /// 画布捏合缩放结束时调用：解冻并立即同步一次正确 frame（带防抖，避免 reflow）。
    func unfreezeAfterZoom() {
        guard isFrozenForZoom else { return }
        isFrozenForZoom = false
        guard pendingBounds.size != .zero else { return }
        // 用 200ms 防抖落地最终 frame（与 resize 拖拽结束行为一致）
        resizeDebounceTask?.cancel()
        resizeDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            self.commitResize()
        }
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
