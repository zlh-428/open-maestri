import AppKit

/// 手绘路径渲染层（节点下方），用于将 DrawingContent 渲染为画布上的笔画。
/// 笔画坐标为节点内部坐标，需结合节点 frame 转换到画布屏幕坐标。
final class DrawingLayerView: NSView {
    override var isFlipped: Bool { true }

    var canvasOrigin: CGPoint = .zero { didSet { needsDisplay = true } }
    var zoom: CGFloat = 1.0 { didSet { needsDisplay = true } }

    /// (节点画布 frame, 内容) 对，由外部在 sync 时更新
    var drawingNodes: [(frame: CGRect, content: ShapeContent)] = [] {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Shape nodes are rendered by ShapeNodeSwiftUIView (SwiftUI layer).
        // This NSView drawing layer is no longer used.
    }

    private func canvasToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - canvasOrigin.x) * zoom,
            y: (point.y - canvasOrigin.y) * zoom
        )
    }
}
