import Foundation
import CoreGraphics
import AppKit

/// 应用全局常量
enum Constants {
    static let schemaVersion = 2
    static let appDataDirectoryName = ".open-maestri"
    static let defaultFontSize: CGFloat = 13
    static let defaultFontFamily = "SF Mono"
    static let autosaveInterval: TimeInterval = 30
    static let backupInterval: TimeInterval = 3600
    static let canvasInitialOrigin = CGPoint(x: 9800, y: 8500)
    static let canvasMinZoom: CGFloat = 0.1
    static let canvasMaxZoom: CGFloat = 3.0
    static let canvasZoomStep: CGFloat = 0.25
    static let canvasGridSpacing: CGFloat = 16
    static let canvasGridLineColor = NSColor(white: 0.90, alpha: 1)
    static let canvasGridLineWidth: CGFloat = 0.5
    static let ropeControlPointCount = 21
    static let ropeBendRatioMin: CGFloat = 1.08
    static let ropeBendRatioMax: CGFloat = 1.15
    static let interAgentServerHost = "127.0.0.1"
    static let terminalMinWidth: CGFloat = 200
    static let terminalMinHeight: CGFloat = 100
    static let noteMinWidth: CGFloat = 120
    static let noteMinHeight: CGFloat = 80
    static let noteDefaultWidth: CGFloat = 260
    static let noteDefaultHeight: CGFloat = 150
    static let noteDefaultColor = "#FEFDE8"
    static let agentIdleTimeout: TimeInterval = 2.0
    static let skillInjectionAnimationDuration: TimeInterval = 0.5
    static let toastDismissDuration: TimeInterval = 2.0
    static let connectionStatusFadeDuration: TimeInterval = 0.15
    static let serverRestartDelay: TimeInterval = 3.0
}

/// 键盘按键代码常量（macOS 物理键码，与语言无关）
enum CanvasKeyCode {
    static let space: UInt16 = 49
    static let tab: UInt16 = 48
}
