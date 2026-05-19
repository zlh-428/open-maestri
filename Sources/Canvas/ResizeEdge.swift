import AppKit

/// 8 方向 Resize 枚举，供 CanvasInteractionHandler 和命中测试使用。
/// 原先定义在已删除的 BaseNodeView（NSView 子类）中，现迁移至此独立文件。
enum ResizeEdge {
    case right, left, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight

    var cursor: NSCursor {
        switch self {
        case .right, .left:             return .resizeLeftRight
        case .top, .bottom:             return .resizeUpDown
        case .topLeft, .bottomRight:    return .crosshair
        case .topRight, .bottomLeft:    return .crosshair
        }
    }
}
