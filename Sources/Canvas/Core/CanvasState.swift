import OSLog
import Foundation
import CoreGraphics

/// 画布状态，@MainActor 强制所有修改在主线程（Epic 2 实现）
@MainActor
@Observable
final class CanvasState {
    var origin: CGPoint = Constants.canvasInitialOrigin
    var zoom: CGFloat = 1.0
    var selectedNodeIds: Set<UUID> = []

    private let logger = Logger.make(category: "CanvasState")
}
