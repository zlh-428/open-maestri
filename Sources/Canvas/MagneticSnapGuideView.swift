import AppKit

/// 磁吸对齐辅助线层（最顶层），替代 CanvasViewportView.drawSnapGuidelines()。
/// 使用 canvasOrigin/zoom 将画布坐标转换为屏幕坐标后绘制。
final class MagneticSnapGuideView: NSView {
    var guidelines: [GuideLine] = [] { didSet { needsDisplay = true } }
    var canvasOrigin: CGPoint = .zero
    var zoom: CGFloat = 1.0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
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
    }

    private func canvasToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - canvasOrigin.x) * zoom,
            y: (point.y - canvasOrigin.y) * zoom
        )
    }
}
