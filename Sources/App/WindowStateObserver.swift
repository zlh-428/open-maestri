import AppKit
import SwiftUI

/// 监控主窗口的全屏状态，供 SwiftUI 视图响应布局变化
@Observable
@MainActor
final class WindowStateObserver {
    static let shared = WindowStateObserver()

    /// 窗口是否处于全屏（最大化）状态
    var isFullScreen: Bool = false

    nonisolated(unsafe) private var notificationObservers: [NSObjectProtocol] = []

    private init() {
        notificationObservers = [
            NotificationCenter.default.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.isFullScreen = true }
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.isFullScreen = false }
            },
        ]
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// 配置主窗口样式（透明 title bar、隐藏标题）
    func configureMainWindow() {
        guard let window = NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // 让内容延伸到 title bar 区域
        window.styleMask.insert(.fullSizeContentView)
    }
}
