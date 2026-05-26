import AppKit

/// 8 方向 Resize 枚举，供 CanvasInteractionHandler 和命中测试使用。
/// 原先定义在已删除的 BaseNodeView（NSView 子类）中，现迁移至此独立文件。
enum ResizeEdge {
    case right, left, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight

    /// macOS 原生 resize 光标（从系统光标资源加载）
    var cursor: NSCursor {
        switch self {
        case .right, .left:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topLeft, .bottomRight:
            return ResizeCursors.nwse
        case .topRight, .bottomLeft:
            return ResizeCursors.nesw
        }
    }
}

// MARK: - 系统原生对角线 Resize 光标

/// 从 macOS 系统光标资源目录加载原生对角线 resize 光标。
/// 路径：HIServices.framework/Resources/cursors/
private enum ResizeCursors {
    /// ↘↖ 对角线（左上-右下 / NW-SE）
    static let nwse: NSCursor = loadSystemCursor(name: "resizenorthwestsoutheast", hotSpot: NSPoint(x: 11, y: 11))
    /// ↗↙ 对角线（右上-左下 / NE-SW）
    static let nesw: NSCursor = loadSystemCursor(name: "resizenortheastsouthwest", hotSpot: NSPoint(x: 11, y: 11))

    private static func loadSystemCursor(name: String, hotSpot: NSPoint) -> NSCursor {
        let basePath = "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors"
        let cursorPath = "\(basePath)/\(name)/cursor.pdf"

        if let image = NSImage(contentsOfFile: cursorPath) {
            return NSCursor(image: image, hotSpot: hotSpot)
        }

        // 降级：使用公开 API 的 resizeLeftRight（不应该发生）
        return .crosshair
    }
}
