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
    /// 当前绘制节点类型（用于决定预览形状：rect/ellipse/diamond/stroke_*/freehand_*）
    var drawingNodeType: String = "rect" { didSet { needsDisplay = true } }

    // MARK: - Stroke 绘制预览（屏幕坐标）
    /// stroke 绘制起点（屏幕坐标，nil = 不绘制）
    var strokePreviewStart: CGPoint? { didSet { needsDisplay = true } }
    /// stroke 绘制终点（屏幕坐标，nil = 不绘制）
    var strokePreviewEnd: CGPoint? { didSet { needsDisplay = true } }

    // MARK: - Freehand 绘制预览（屏幕坐标）
    /// freehand 采样点序列（屏幕坐标，空 = 不绘制）
    var freehandPreviewPoints: [CGPoint] = [] { didSet { needsDisplay = true } }
    /// freehand 笔触颜色（默认黑色）
    var freehandPreviewColor: NSColor = .black { didSet { needsDisplay = true } }
    /// freehand 笔触宽度
    var freehandPreviewWidth: CGFloat = 2.0 { didSet { needsDisplay = true } }

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

        // 节点绘制预览（根据 drawingNodeType 绘制对应形状）
        if let rect = drawingRect {
            drawShapePreview(in: rect)
        }

        // Stroke 绘制预览（直线/箭头）
        if let start = strokePreviewStart, let end = strokePreviewEnd {
            drawStrokePreview(from: start, to: end)
        }

        // Freehand 绘制预览（自由笔/荧光笔）
        if freehandPreviewPoints.count >= 2 {
            drawFreehandPreview()
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

    // MARK: - 形状预览绘制（draw.io 风格：虚线轮廓 + 极淡填充）

    private func drawShapePreview(in rect: CGRect) {
        let strokeColor = NSColor.systemBlue.withAlphaComponent(0.7)
        let fillColor = NSColor.systemBlue.withAlphaComponent(0.06)
        let lineWidth: CGFloat = 1.5
        let dashPattern: [CGFloat] = [6, 4]

        let path: NSBezierPath
        switch drawingNodeType {
        case "ellipse":
            path = NSBezierPath(ovalIn: rect)
        case "diamond":
            path = diamondPath(in: rect)
        default:
            // rect 及其他 shape 类型：圆角矩形
            path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        }

        path.lineWidth = lineWidth
        path.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        fillColor.setFill()
        strokeColor.setStroke()
        path.fill()
        path.stroke()
    }

    /// 菱形路径（四个顶点：上中、右中、下中、左中）
    private func diamondPath(in rect: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.line(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.line(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.line(to: CGPoint(x: rect.minX, y: rect.midY))
        path.close()
        return path
    }

    // MARK: - Stroke 预览绘制（draw.io 风格：蓝色实线 + 起终点圆点）

    private func drawStrokePreview(from start: CGPoint, to end: CGPoint) {
        let strokeColor = NSColor.systemBlue.withAlphaComponent(0.85)

        // 主线段
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = 2.0
        path.lineCapStyle = .round
        strokeColor.setStroke()
        path.stroke()

        // 箭头类型：在终点绘制箭头头部
        if drawingNodeType == "stroke_arrow" {
            drawArrowHead(at: end, from: start, color: strokeColor)
        }

        // 起点圆点
        drawEndpointDot(at: start, color: strokeColor, radius: 4)
        // 终点圆点
        drawEndpointDot(at: end, color: strokeColor, radius: 4)
    }

    /// 绘制箭头头部（draw.io 风格：实心三角）
    private func drawArrowHead(at tip: CGPoint, from tail: CGPoint, color: NSColor) {
        let dx = tip.x - tail.x
        let dy = tip.y - tail.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 1 else { return }

        let ux = dx / len
        let uy = dy / len
        let arrowLen: CGFloat = 14
        let arrowWidth: CGFloat = 8

        let base = CGPoint(x: tip.x - ux * arrowLen, y: tip.y - uy * arrowLen)
        let left = CGPoint(x: base.x - uy * arrowWidth, y: base.y + ux * arrowWidth)
        let right = CGPoint(x: base.x + uy * arrowWidth, y: base.y - ux * arrowWidth)

        let arrowPath = NSBezierPath()
        arrowPath.move(to: tip)
        arrowPath.line(to: left)
        arrowPath.line(to: right)
        arrowPath.close()
        color.setFill()
        arrowPath.fill()
    }

    /// 绘制端点圆点（白色填充 + 蓝色描边）
    private func drawEndpointDot(at point: CGPoint, color: NSColor, radius: CGFloat) {
        let dotRect = CGRect(x: point.x - radius, y: point.y - radius,
                             width: radius * 2, height: radius * 2)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        NSColor.white.setFill()
        dotPath.fill()
        color.setStroke()
        dotPath.lineWidth = 1.5
        dotPath.stroke()
    }

    // MARK: - Freehand 预览绘制（Catmull-Rom 平滑曲线）

    private func drawFreehandPreview() {
        let pts = freehandPreviewPoints
        guard pts.count >= 2 else { return }

        let path: NSBezierPath
        if pts.count > 3 {
            path = catmullRomPath(pts)
        } else {
            path = NSBezierPath()
            path.move(to: pts[0])
            for pt in pts.dropFirst() { path.line(to: pt) }
        }

        path.lineWidth = freehandPreviewWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        freehandPreviewColor.setStroke()
        path.stroke()
    }

    /// Catmull-Rom 样条插值（与 FreehandNodeSwiftUIView 保持一致）
    private func catmullRomPath(_ pts: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: pts[0])
        for i in 0..<pts.count - 1 {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]
            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6,
                              y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6,
                              y: p2.y - (p3.y - p1.y) / 6)
            path.curve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
        }
        return path
    }

    func clear() {
        guidelines = []
        selectionRect = nil
        drawingRect = nil
        strokePreviewStart = nil
        strokePreviewEnd = nil
        freehandPreviewPoints = []
    }

    private func canvasToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - canvasOrigin.x) * zoom,
            y: (point.y - canvasOrigin.y) * zoom
        )
    }
}
