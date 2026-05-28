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
    /// 当前绘制节点类型（由 CanvasViewportView 同步，用于预览样式判断）
    var drawingNodeType: String = "terminal"
    /// stroke 预览路径（屏幕坐标），包含起点、终点和节点类型
    var strokePreviewPath: (start: CGPoint, end: CGPoint, type: String)? {
        didSet {
            if strokePreviewPath != nil { startAnimation() } else { stopAnimation() }
            needsDisplay = true
        }
    }
    /// freehand 预览点列表（屏幕坐标）
    var freehandPreviewPoints: [CGPoint]? {
        didSet {
            if freehandPreviewPoints != nil { startAnimation() } else { stopAnimation() }
            needsDisplay = true
        }
    }
    var canvasOrigin: CGPoint = .zero
    var zoom: CGFloat = 1.0

    // MARK: - 行进虚线动画

    private var animationTimer: Timer?
    private var dashPhase: CGFloat = 0

    private func startAnimation() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            dashPhase -= 0.5
            needsDisplay = true
        }
    }

    private func stopAnimation() {
        guard strokePreviewPath == nil && freehandPreviewPoints == nil else { return }
        animationTimer?.invalidate()
        animationTimer = nil
        dashPhase = 0
    }

    // MARK: - 绘制

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

        // stroke 预览（箭头/直线）—— 行进虚线
        if let preview = strokePreviewPath {
            drawStrokePreview(start: preview.start, end: preview.end, type: preview.type)
        }

        // freehand 预览（钢笔/涂鸦）—— 行进虚线
        if let pts = freehandPreviewPoints, pts.count >= 2 {
            drawFreehandPreview(points: pts)
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

    // MARK: - 预览绘制辅助

    private func drawStrokePreview(start: CGPoint, end: CGPoint, type: String) {
        let path = NSBezierPath()
        path.move(to: start)
        if type == "stroke_arrow" {
            let ctrl = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            path.curve(to: end, controlPoint1: ctrl, controlPoint2: ctrl)
        } else {
            path.line(to: end)
        }
        path.lineWidth = 2.0
        path.lineCapStyle = .round
        path.setLineDash([6, 4], count: 2, phase: dashPhase)
        NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
        path.stroke()

        // 起点和终点圆点
        drawEndpointDot(at: start)
        drawEndpointDot(at: end)
    }

    private func drawFreehandPreview(points: [CGPoint]) {
        let path = NSBezierPath()
        path.move(to: points[0])
        if points.count > 3 {
            for i in 0..<points.count - 1 {
                let p0 = points[max(i - 1, 0)]
                let p1 = points[i]
                let p2 = points[i + 1]
                let p3 = points[min(i + 2, points.count - 1)]
                let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                path.curve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
            }
        } else {
            for pt in points.dropFirst() { path.line(to: pt) }
        }
        path.lineWidth = 2.0
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.setLineDash([6, 4], count: 2, phase: dashPhase)
        NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
        path.stroke()
    }

    private func drawEndpointDot(at point: CGPoint) {
        let r: CGFloat = 4
        let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
        let dot = NSBezierPath(ovalIn: rect)
        NSColor.white.setFill()
        dot.fill()
        NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
        dot.lineWidth = 1.5
        dot.stroke()
    }

    func clear() {
        guidelines = []
        selectionRect = nil
        drawingRect = nil
        strokePreviewPath = nil
        freehandPreviewPoints = nil
    }

    private func canvasToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - canvasOrigin.x) * zoom,
            y: (point.y - canvasOrigin.y) * zoom
        )
    }
}
