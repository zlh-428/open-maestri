import AppKit

/// 画布背景层（点阵/纯色/透明），替代 CanvasViewportView.drawLineGrid。
/// 随 canvasOrigin/zoom/backgroundMode 变化重绘。
final class CanvasBackground: NSView {
    override var isFlipped: Bool { true }

    var canvasOrigin: CGPoint = .zero { didSet { needsDisplay = true } }
    var zoom: CGFloat = 1.0 { didSet { needsDisplay = true } }
    var backgroundMode: String = "dotGrid" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        switch backgroundMode {
        case "dotGrid":
            drawLineGrid(in: dirtyRect)
        case "solid":
            NSColor(white: 0.98, alpha: 1).setFill()
            dirtyRect.fill()
        case "transparent":
            NSColor.clear.setFill()
            dirtyRect.fill()
        default:
            drawLineGrid(in: dirtyRect)
        }
    }

    private func drawLineGrid(in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(rect)

        let gridSpacing: CGFloat = Constants.canvasGridSpacing * zoom
        let offsetX = -(canvasOrigin.x * zoom).truncatingRemainder(dividingBy: gridSpacing)
        let offsetY = -(canvasOrigin.y * zoom).truncatingRemainder(dividingBy: gridSpacing)

        ctx.setStrokeColor(Constants.canvasGridLineColor.cgColor)
        ctx.setLineWidth(Constants.canvasGridLineWidth)

        let startX = rect.minX - rect.minX.truncatingRemainder(dividingBy: gridSpacing) + offsetX
        var x = startX
        while x <= rect.maxX {
            ctx.move(to: CGPoint(x: x, y: rect.minY))
            ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += gridSpacing
        }

        let startY = rect.minY - rect.minY.truncatingRemainder(dividingBy: gridSpacing) + offsetY
        var y = startY
        while y <= rect.maxY {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += gridSpacing
        }

        ctx.strokePath()
    }
}
