import AppKit

// MARK: - 画布命中测试结果

/// 语义化命中区域，供 CanvasInteractionHandler 使用
enum CanvasHitTestResult {
    case canvas
    case nodeHeader(UUID)
    case nodeFooter(UUID)
    case nodeContent(UUID, NSView)
    case nodeResize(UUID, ResizeEdge)
    case nodeRotateHandle(UUID)
}

// MARK: - 画布交互状态机

/// 替换 CanvasViewportView 上的所有散落交互状态变量，
/// 所有状态存储在 associated values 中，避免状态不一致。
enum CanvasInteraction {
    case idle
    /// 鼠标已按下但尚未确定是点击还是拖动；
    /// contentTarget 非 nil 表示已将 mouseDown 透传给该视图（Terminal 等内容区）
    case mayDragNode(UUID, startMouse: CGPoint, startFrame: CGRect, contentTarget: NSView?)
    case draggingNode(UUID, startMouse: CGPoint, startFrame: CGRect)
    case batchDragging([UUID: CGRect], primaryId: UUID, startMouse: CGPoint)
    case resizingNode(UUID, edge: ResizeEdge, startFrame: CGRect, startMouse: CGPoint)
    /// 正在旋转 shape 节点
    case rotatingNode(UUID, startAngle: CGFloat, nodeCenter: CGPoint)
    case marquee(start: CGPoint)
    case panCanvas(startOrigin: CGPoint, startMouse: CGPoint)
    case drawing(start: CGPoint)
    /// 正在绘制 stroke（直线/箭头）节点
    case drawingStroke(start: CGPoint)
    /// 正在绘制 freehand（自由笔）节点；points 为屏幕坐标采样序列
    case drawingFreehand(points: [CGPoint])
    /// 正在拖拽 stroke 控制点（起点/终点/贝塞尔控制点）
    case draggingStrokePoint(UUID, pointRole: String, startContent: StrokeContent, startFrame: CGRect)
    /// 鼠标正在与节点内容区交互（如终端文字选中）；事件转发给 contentTarget
    case contentInteraction(UUID, contentTarget: NSView)
}

// MARK: - CanvasViewportView selectionRect helper

extension CanvasViewportView {
    /// 当前框选矩形（从 interaction.marquee 状态读取）
    var selectionRect: CGRect? {
        guard case .marquee(let start) = interaction,
              let current = marqueeCurrentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }
}
