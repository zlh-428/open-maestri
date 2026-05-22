import SwiftUI
import AppKit
import SwiftTerm

/// 终端嵌入视图（NSViewRepresentable 包装 MaestroTerminalView）
/// makeNSView 返回 MaestroTerminalView（NSView 直接子类），Coordinator 持有 provider
struct TerminalEmbeddedView: NSViewRepresentable {
    let terminalId: UUID
    let command: String
    let workingDirectory: String
    var serverPort: UInt16 = 0
    var workspaceId: UUID?
    /// 节点级主题/字体覆盖（nil 表示跟随全局 Preferences）
    var nodeThemeId: String?
    var nodeFontFamily: String?
    var nodeFontSize: CGFloat?

    // MARK: - Coordinator
    @MainActor
    final class Coordinator: NSObject {
        var provider: SwiftTermProvider?
        var isAttached: Bool = false
        var lastTheme: String = ""
        var lastFontName: String = ""
        var lastFontSize: CGFloat = 0

        private var providerReadyObserver: NSObjectProtocol?
        private var shellReadyObserver: NSObjectProtocol?

        func setupObservers(terminalId: UUID, maestroView: MaestroTerminalView) {
            teardownObservers()
            providerReadyObserver = NotificationCenter.default.addObserver(
                forName: .terminalProviderReady, object: nil, queue: .main
            ) { [weak self, weak maestroView] notif in
                guard let tid = notif.userInfo?["terminalId"] as? UUID, tid == terminalId,
                      let self, let maestroView else { return }
                Task { @MainActor in
                    self.attachIfNeeded(to: maestroView, terminalId: terminalId)
                }
            }
            shellReadyObserver = NotificationCenter.default.addObserver(
                forName: .terminalShellReady, object: nil, queue: .main
            ) { [weak maestroView] notif in
                guard let tid = notif.userInfo?["terminalId"] as? UUID, tid == terminalId,
                      let wsId = notif.userInfo?["workspaceId"] as? UUID else { return }
                Task { @MainActor in
                    maestroView?.loadScrollback(workspaceId: wsId)
                }
            }
        }

        func teardownObservers() {
            if let obs = providerReadyObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = shellReadyObserver { NotificationCenter.default.removeObserver(obs) }
            providerReadyObserver = nil
            shellReadyObserver = nil
        }

        @MainActor
        func attachIfNeeded(to maestroView: MaestroTerminalView, terminalId: UUID) {
            guard !isAttached,
                  let provider = TerminalManager.shared.providers[terminalId] else { return }
            self.provider = provider
            maestroView.attach(provider: provider)
            isAttached = true
        }

        deinit {
            // deinit 是 nonisolated，把 observer 引用拷出来异步清理
            let obs1 = providerReadyObserver
            let obs2 = shellReadyObserver
            if let obs1 { NotificationCenter.default.removeObserver(obs1) }
            if let obs2 { NotificationCenter.default.removeObserver(obs2) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    func makeNSView(context: Context) -> MaestroTerminalView {
        let maestroView = MaestroTerminalView(terminalId: terminalId)
        maestroView.autoresizingMask = [.width, .height]
        context.coordinator.setupObservers(terminalId: terminalId, maestroView: maestroView)
        // provider 可能已就绪（工作区切换回来）
        context.coordinator.attachIfNeeded(to: maestroView, terminalId: terminalId)
        return maestroView
    }

    @MainActor
    func updateNSView(_ nsView: MaestroTerminalView, context: Context) {
        // 只做主题/字体差量更新（resize 由 MaestroTerminalView.layout() 处理）
        guard context.coordinator.isAttached, let tv = nsView.terminalView else { return }
        let prefs = (try? PersistenceManager.shared.loadPreferences()) ?? Preferences()

        // 优先用节点自身设置，回退到全局 Preferences
        let effectiveThemePref = nodeThemeId ?? prefs.terminalTheme
        let themeId = TerminalThemeRegistry.resolveThemeId(from: effectiveThemePref)
        if context.coordinator.lastTheme != themeId {
            TerminalThemeRegistry.shared.apply(themeId: themeId, to: tv)
            context.coordinator.lastTheme = themeId
        }

        let effectiveFamily = nodeFontFamily ?? prefs.terminalFontFamily
        let effectiveSize = nodeFontSize ?? prefs.terminalFontSize
        if context.coordinator.lastFontName != effectiveFamily
            || context.coordinator.lastFontSize != effectiveSize {
            tv.font = resolveTerminalFont(family: effectiveFamily, size: effectiveSize)
            context.coordinator.lastFontName = effectiveFamily
            context.coordinator.lastFontSize = effectiveSize
        }
    }

    @MainActor
    static func dismantleNSView(_ nsView: MaestroTerminalView, coordinator: Coordinator) {
        coordinator.teardownObservers()
        nsView.detach()
        coordinator.isAttached = false
        coordinator.provider = nil
    }
}
