import AppKit

/// 8 方向 Resize 枚举，供 CanvasInteractionHandler 和命中测试使用。
/// 原先定义在已删除的 BaseNodeView（NSView 子类）中，现迁移至此独立文件。
enum ResizeEdge {
    case right, left, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight

    /// macOS 原生风格的 resize 光标
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

// MARK: - 对角线 Resize 光标

/// 生成 macOS 原生风格的对角线 resize 双箭头光标。
/// 通过 CoreGraphics 绘制，无需私有 API。
private enum ResizeCursors {
    /// ↘↖ 对角线（左上-右下）
    static let nwse: NSCursor = makeDiagonalCursor(angle: .pi / 4)
    /// ↗↙ 对角线（右上-左下）
    static let nesw: NSCursor = makeDiagonalCursor(angle: -.pi / 4)

    private static func makeDiagonalCursor(angle: CGFloat) -> NSCursor {
        let size: CGFloat = 20
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: rect.midX, y: rect.midY)

            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: angle)

            // 箭头线参数
            let halfLen: CGFloat = 7.5
            let arrowSize: CGFloat = 4.0
            let lineWidth: CGFloat = 1.5

            // 绘制白色描边（阴影效果）
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(lineWidth + 2)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            drawArrowPath(ctx: ctx, halfLen: halfLen, arrowSize: arrowSize)
            ctx.strokePath()

            // 绘制黑色主体
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(lineWidth)
            drawArrowPath(ctx: ctx, halfLen: halfLen, arrowSize: arrowSize)
            ctx.strokePath()

            ctx.restoreGState()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }

    private static func drawArrowPath(ctx: CGContext, halfLen: CGFloat, arrowSize: CGFloat) {
        // 主轴线（垂直方向，旋转后变为对角线）
        ctx.move(to: CGPoint(x: 0, y: -halfLen))
        ctx.addLine(to: CGPoint(x: 0, y: halfLen))

        // 上箭头
        ctx.move(to: CGPoint(x: -arrowSize, y: -halfLen + arrowSize))
        ctx.addLine(to: CGPoint(x: 0, y: -halfLen))
        ctx.addLine(to: CGPoint(x: arrowSize, y: -halfLen + arrowSize))

        // 下箭头
        ctx.move(to: CGPoint(x: -arrowSize, y: halfLen - arrowSize))
        ctx.addLine(to: CGPoint(x: 0, y: halfLen))
        ctx.addLine(to: CGPoint(x: arrowSize, y: halfLen - arrowSize))
    }
}
