import AppKit
import SwiftUI

/// 监控主窗口的全屏状态，供 SwiftUI 视图响应布局变化
@Observable
@MainActor
final class WindowStateObserver {
    static let shared = WindowStateObserver()

    /// 窗口是否处于全屏（最大化）状态
    var isFullScreen: Bool = false

    private init() {
        // 监听窗口全屏进入/退出通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidEnterFullScreen),
            name: NSWindow.didEnterFullScreenNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidExitFullScreen),
            name: NSWindow.didExitFullScreenNotification,
            object: nil
        )
    }

    @objc private func windowDidEnterFullScreen(_ notification: Notification) {
        isFullScreen = true
    }

    @objc private func windowDidExitFullScreen(_ notification: Notification) {
        isFullScreen = false
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
