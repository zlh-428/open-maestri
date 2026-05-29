import AppKit
import CoreGraphics

/// 右下角 Minimap（Story 2.4 AC）
/// - 显示当前画布全貌缩略图，蓝框标记视口位置
/// - 点击任意位置：视口跳转到对应区域（300ms 动画）
/// - 实时更新（节点移动/添加时）
final class MinimapView: NSView {
    override var isFlipped: Bool { true }

    // MARK: - 数据

    /// 所有节点的画布 frame
    var nodeFrames: [CGRect] = [] { didSet { needsDisplay = true } }

    /// 当前视口（画布坐标）
    var viewportRect: CGRect = .zero { didSet { needsDisplay = true } }

    /// 画布有效区域（所有节点的 bounding box，带 padding）
    var canvasBounds: CGRect = CGRect(x: 9600, y: 8300, width: 600, height: 600)

    /// 点击跳转回调（传入目标画布原点）
    var onJumpTo: ((CGPoint) -> Void)?

    // MARK: - 外观

    private let backgroundColor = NSColor.black.withAlphaComponent(0.75)
    private let nodeColor = NSColor.white.withAlphaComponent(0.5)
    private let viewportColor = NSColor.systemBlue.withAlphaComponent(0.3)
    private let viewportBorderColor = NSColor.systemBlue

    // MARK: - 初始化

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        layer?.borderWidth = 0.5
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard NSGraphicsContext.current?.cgContext != nil else { return }

        backgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()

        let scale = minimapScale()

        // 绘制节点矩形
        nodeColor.setFill()
        for nodeFrame in nodeFrames {
            let mapped = mapToMinimap(nodeFrame, scale: scale)
            let path = NSBezierPath(roundedRect: mapped, xRadius: 2, yRadius: 2)
            path.fill()
        }

        // 绘制视口蓝框
        let mappedViewport = mapToMinimap(viewportRect, scale: scale)
        viewportColor.setFill()
        NSBezierPath(roundedRect: mappedViewport, xRadius: 2, yRadius: 2).fill()
        viewportBorderColor.setStroke()
        let borderPath = NSBezierPath(roundedRect: mappedViewport, xRadius: 2, yRadius: 2)
        borderPath.lineWidth = 1.0
        borderPath.stroke()
    }

    // MARK: - 坐标映射

    private func minimapScale() -> CGFloat {
        let scaleX = bounds.width / canvasBounds.width
        let scaleY = bounds.height / canvasBounds.height
        return min(scaleX, scaleY) * 0.9
    }

    private func mapToMinimap(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let padding: CGFloat = 4
        let ox = (rect.origin.x - canvasBounds.minX) * scale + padding
        let oy = (rect.origin.y - canvasBounds.minY) * scale + padding
        return CGRect(
            x: ox, y: oy,
            width: max(rect.width * scale, 3),
            height: max(rect.height * scale, 3)
        )
    }

    private func minimapPointToCanvas(_ point: CGPoint) -> CGPoint {
        let padding: CGFloat = 4
        let scale = minimapScale()
        let cx = (point.x - padding) / scale + canvasBounds.minX
        let cy = (point.y - padding) / scale + canvasBounds.minY
        return CGPoint(x: cx, y: cy)
    }

    // MARK: - 点击跳转（Story 2.4 AC：300ms 动画）

    override func mouseDown(with event: NSEvent) {
        let click = convert(event.locationInWindow, from: nil)
        let canvasPoint = minimapPointToCanvas(click)
        onJumpTo?(canvasPoint)
    }

    // MARK: - 外部更新 API

    /// 根据当前节点列表和视口更新 Minimap
    func update(nodes: [CGRect], viewport: CGRect) {
        if nodes.isEmpty {
            canvasBounds = CGRect(x: 9600, y: 8300, width: 800, height: 600)
        } else {
            var minX = CGFloat.infinity, maxX = -CGFloat.infinity
            var minY = CGFloat.infinity, maxY = -CGFloat.infinity
            for r in nodes {
                minX = min(minX, r.minX); maxX = max(maxX, r.maxX)
                minY = min(minY, r.minY); maxY = max(maxY, r.maxY)
            }
            canvasBounds = CGRect(
                x: minX - 100,
                y: minY - 100,
                width: maxX - minX + 200,
                height: maxY - minY + 200
            )
        }
        nodeFrames = nodes
        viewportRect = viewport
    }
}
