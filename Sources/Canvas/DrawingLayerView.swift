import AppKit

/// 手绘路径渲染层（节点下方），用于将 DrawingContent 渲染为画布上的笔画。
/// 笔画坐标为节点内部坐标，需结合节点 frame 转换到画布屏幕坐标。
final class DrawingLayerView: NSView {
    override var isFlipped: Bool { true }

    var canvasOrigin: CGPoint = .zero { didSet { needsDisplay = true } }
    var zoom: CGFloat = 1.0 { didSet { needsDisplay = true } }

    /// (节点画布 frame, 内容) 对，由外部在 sync 时更新
    var drawingNodes: [(frame: CGRect, content: DrawingContent)] = [] {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !drawingNodes.isEmpty,
              let ctx = NSGraphicsContext.current?.cgContext else { return }

        for (frame, content) in drawingNodes {
            let screenOrigin = canvasToScreen(frame.origin)
            let scaleX = frame.width * zoom
            let scaleY = frame.height * zoom

            ctx.saveGState()
            ctx.translateBy(x: screenOrigin.x, y: screenOrigin.y)

            for stroke in content.strokes {
                guard stroke.points.count > 1 else { continue }
                let bezier = NSBezierPath()
                bezier.lineWidth = stroke.width
                bezier.lineCapStyle = .round
                bezier.lineJoinStyle = .round
                let firstPt = CGPoint(
                    x: stroke.points[0][0] * scaleX / frame.width,
                    y: stroke.points[0][1] * scaleY / frame.height
                )
                bezier.move(to: firstPt)
                for i in 1..<stroke.points.count {
                    let pt = CGPoint(
                        x: stroke.points[i][0] * scaleX / frame.width,
                        y: stroke.points[i][1] * scaleY / frame.height
                    )
                    bezier.line(to: pt)
                }
                (NSColor(hex: stroke.color) ?? .black).setStroke()
                bezier.stroke()
            }

            ctx.restoreGState()
        }
    }

    private func canvasToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - canvasOrigin.x) * zoom,
            y: (point.y - canvasOrigin.y) * zoom
        )
    }
}
