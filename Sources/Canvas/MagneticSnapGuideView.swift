import AppKit

/// 磁吸对齐辅助线层（最顶层），替代 CanvasViewportView.drawSnapGuidelines()。
/// 同时负责绘制框选矩形和节点绘制预览矩形（因为此层在所有节点层之上）。
/// 使用 canvasOrigin/zoom 将画布坐标转换为屏幕坐标后绘制。
final class MagneticSnapGuideView: NSView {
    override var isFlipped: Bool { true }

    var guidelines: [GuideLine] = [] { didSet { needsDisplay = true } }
    /// 框选矩形（屏幕坐标，nil = 不绘制）
    var selectionRect: CGRect? { didSet { needsDisplay = true } }
    /// 节点绘制预览矩形（屏幕坐标，nil = 不绘制）
    var drawingRect: CGRect? { didSet { needsDisplay = true } }
    var canvasOrigin: CGPoint = .zero
    var zoom: CGFloat = 1.0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 框选矩形
        if let rect = selectionRect, rect.width > 2 || rect.height > 2 {
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 1.0
            NSColor.systemBlue.withAlphaComponent(0.4).setStroke()
            NSColor.systemBlue.withAlphaComponent(0.08).setFill()
            path.stroke()
            path.fill()
        }

        // 节点绘制预览矩形
        if let rect = drawingRect {
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            path.lineWidth = 1.5
            path.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.systemBlue.withAlphaComponent(0.6).setStroke()
            NSColor.systemBlue.withAlphaComponent(0.05).setFill()
            path.stroke()
            path.fill()
        }

        guard !guidelines.isEmpty else { return }

        NSColor.systemBlue.withAlphaComponent(0.7).setStroke()
        for line in guidelines {
            let path = NSBezierPath()
            path.lineWidth = 1.0
            path.setLineDash([4, 3], count: 2, phase: 0)
            if line.axis == .vertical {
                let screenX = canvasToScreen(CGPoint(x: line.position, y: 0)).x
                let screenStart = canvasToScreen(CGPoint(x: 0, y: line.start)).y
                let screenEnd = canvasToScreen(CGPoint(x: 0, y: line.end)).y
                path.move(to: CGPoint(x: screenX, y: screenStart))
                path.line(to: CGPoint(x: screenX, y: screenEnd))
            } else {
                let screenY = canvasToScreen(CGPoint(x: 0, y: line.position)).y
                let screenStart = canvasToScreen(CGPoint(x: line.start, y: 0)).x
                let screenEnd = canvasToScreen(CGPoint(x: line.end, y: 0)).x
                path.move(to: CGPoint(x: screenStart, y: screenY))
                path.line(to: CGPoint(x: screenEnd, y: screenY))
            }
            path.stroke()
        }
    }

    func clear() {
        guidelines = []
        selectionRect = nil
        drawingRect = nil
    }

    private func canvasToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - canvasOrigin.x) * zoom,
            y: (point.y - canvasOrigin.y) * zoom
        )
    }
}
