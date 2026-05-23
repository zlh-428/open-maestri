import AppKit

extension CanvasViewportView {

    // MARK: - 节点绘制模式

    /// 点击创建时的默认节点尺寸（画布坐标）
    func defaultNodeSize(for nodeType: String) -> CGSize {
        switch nodeType {
        case "terminal":
            return CGSize(width: 600, height: 400)
        case "stickyNote":
            return CGSize(width: 300, height: 240)
        case "portal":
            return CGSize(width: 500, height: 380)
        case "fileTree":
            return CGSize(width: 360, height: 480)
        case "text":
            return CGSize(width: 200, height: 60)
        case "drawing":
            return CGSize(width: 400, height: 300)
        default:
            return CGSize(width: 400, height: 300)
        }
    }

    // MARK: - 连线辅助

    /// 从视图（或其子视图）反查所属节点 ID
    /// 先尝试 O(1) 直接映射缓存，未命中时走 O(n) 祖先链遍历
    func nodeId(for view: NSView?) -> UUID? {
        guard let v = view else { return nil }
        if let id = viewToNodeId[ObjectIdentifier(v)] { return id }
        for (id, nodeView) in nodeViews {
            if v.isDescendant(of: nodeView) { return id }
        }
        return nil
    }

    func handleConnectionClick(nodeId: UUID) {
        if let fromId = connectingFromNodeId {
            // 第二次点击：完成连线
            if fromId != nodeId {
                onConnectionCreated?(fromId, nodeId)
            }
            connectingFromNodeId = nil
            connectionDragPoint = nil
            // 连线完成后退出连线模式（通知 SwiftUI 层更新 isConnecting）
            isInConnectingMode = false
        } else {
            // 第一次点击：设置起点，选中节点
            connectingFromNodeId = nodeId
            selectedNodeIds = [nodeId]
            // 开启鼠标跟踪
            for ta in trackingAreas { removeTrackingArea(ta) }
            addTrackingArea(makeTrackingArea())
        }
        needsDisplay = true
    }

    func makeTrackingArea() -> NSTrackingArea {
        NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
    }

    // MARK: - 网格吸附

    /// 将节点 frame 的四条边吸附到背景网格线（与 drawLineGrid 使用的坐标系一致）
    /// 分别对 left/right/top/bottom 四边取整，选择位移量最小的那条边对齐
    func snapToGrid(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let grid = Constants.canvasGridSpacing

        let left   = origin.x
        let right  = origin.x + size.width
        let bottom = origin.y
        let top    = origin.y + size.height

        let snappedLeft   = (left   / grid).rounded() * grid
        let snappedRight  = (right  / grid).rounded() * grid
        let snappedBottom = (bottom / grid).rounded() * grid
        let snappedTop    = (top    / grid).rounded() * grid

        let dx = abs(snappedLeft - left) <= abs(snappedRight - right)
            ? snappedLeft - left
            : snappedRight - right
        let dy = abs(snappedBottom - bottom) <= abs(snappedTop - top)
            ? snappedBottom - bottom
            : snappedTop - top

        return CGPoint(x: origin.x + dx, y: origin.y + dy)
    }

    // MARK: - 绘制矩形预览

    func drawDrawingRect() {
        guard isInDrawingMode,
              case .drawing(let start) = interaction,
              let current = drawingCurrentPoint else { return }
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        path.lineWidth = 1.5
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.systemBlue.withAlphaComponent(0.6).setStroke()
        NSColor.systemBlue.withAlphaComponent(0.05).setFill()
        path.stroke()
        path.fill()
    }

    // MARK: - 框选矩形绘制

    func drawSelectionRect() {
        guard let rect = selectionRect, rect.width > 2 || rect.height > 2 else { return }
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.0
        NSColor.systemBlue.withAlphaComponent(0.4).setStroke()
        NSColor.systemBlue.withAlphaComponent(0.08).setFill()
        path.stroke()
        path.fill()
    }

    // MARK: - 临时连线绘制（连线工具拖动时，使用物理下垂曲线）

    func drawTemporaryConnection() {
        guard let fromId = connectingFromNodeId,
              let fromCanvasFrame = nodeCanvasFrames[fromId] else { return }
        let fromScreenFrame = canvasRectToScreen(fromCanvasFrame)

        // 如果鼠标还没移动（刚进入连线模式），显示四个边缘的连接点指示器
        guard let toPoint = connectionDragPoint else {
            drawEdgeConnectors(on: fromScreenFrame)
            return
        }
        // 计算从节点边缘出发的锚点（向鼠标方向与边框的交点）
        let fromCenter = CGPoint(x: fromScreenFrame.midX, y: fromScreenFrame.midY)
        let fromPoint = Self.edgeAnchorScreen(of: fromScreenFrame, center: fromCenter, toward: toPoint)

        // 使用静态悬链线计算（带自然下垂效果）
        let catenaryPoints = RopeSimulation.computeStaticCatenary(from: fromPoint, to: toPoint)

        guard catenaryPoints.count >= 2 else { return }

        // 使用折线绘制（21 个控制点足够密集，视觉上近似平滑曲线）
        let path = NSBezierPath()
        path.move(to: catenaryPoints[0])
        for i in 1..<catenaryPoints.count {
            path.line(to: catenaryPoints[i])
        }
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
        path.stroke()

        // 起点连接点指示器（在节点边缘出发点画小圆圈）
        let connectorRadius: CGFloat = 5.0
        let connectorRect = CGRect(
            x: fromPoint.x - connectorRadius,
            y: fromPoint.y - connectorRadius,
            width: connectorRadius * 2,
            height: connectorRadius * 2
        )
        NSColor.systemBlue.setFill()
        NSBezierPath(ovalIn: connectorRect).fill()
        NSColor.white.setFill()
        let innerRadius: CGFloat = 2.5
        let innerRect = CGRect(
            x: fromPoint.x - innerRadius,
            y: fromPoint.y - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        )
        NSBezierPath(ovalIn: innerRect).fill()

        // 源节点边框高亮（淡蓝色）
        let borderPath = NSBezierPath(roundedRect: fromScreenFrame, xRadius: 6, yRadius: 6)
        borderPath.lineWidth = 1.5
        NSColor.systemBlue.withAlphaComponent(0.4).setStroke()
        borderPath.stroke()
    }

    // MARK: - 连接点指示器

    /// 在节点四个边缘中点绘制连接点圆圈（连线模式激活但鼠标未移动时）
    private func drawEdgeConnectors(on frame: CGRect) {
        let midPoints = [
            CGPoint(x: frame.midX, y: frame.minY),  // 上
            CGPoint(x: frame.midX, y: frame.maxY),  // 下
            CGPoint(x: frame.minX, y: frame.midY),  // 左
            CGPoint(x: frame.maxX, y: frame.midY),  // 右
        ]
        let radius: CGFloat = 5.0
        let innerRadius: CGFloat = 2.5

        // 节点边框高亮
        let borderPath = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
        borderPath.lineWidth = 1.5
        NSColor.systemBlue.withAlphaComponent(0.4).setStroke()
        borderPath.stroke()

        // 四个连接点
        for pt in midPoints {
            let outerRect = CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2)
            NSColor.systemBlue.setFill()
            NSBezierPath(ovalIn: outerRect).fill()
            let innerRect = CGRect(x: pt.x - innerRadius, y: pt.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: innerRect).fill()
        }
    }

    // MARK: - 边缘锚点计算（屏幕坐标）

    /// 计算从节点边框出发的锚点（屏幕坐标版本）
    /// 从 frame 中心向 target 方向做射线，返回与边框的交点
    static func edgeAnchorScreen(of frame: CGRect, center: CGPoint, toward target: CGPoint) -> CGPoint {
        let dx = target.x - center.x
        let dy = target.y - center.y
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return center }

        let halfW = frame.width / 2.0
        let halfH = frame.height / 2.0
        var t: CGFloat = .greatestFiniteMagnitude

        if abs(dx) > 0.001 {
            let tx = halfW / abs(dx)
            if tx < t { t = tx }
        }
        if abs(dy) > 0.001 {
            let ty = halfH / abs(dy)
            if ty < t { t = ty }
        }

        return CGPoint(x: center.x + dx * t, y: center.y + dy * t)
    }

    // MARK: - Finder 文件拖入（创建 Note 节点）

    /// 注册拖放目标（在 setup() 调用）
    func registerDragTypes() {
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard containsFileURLs(sender) else { return [] }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard containsFileURLs(sender) else { return [] }
        // 高亮目标节点（如果鼠标在节点上方）
        let loc = convert(sender.draggingLocation, from: nil)
        updateDropTargetHighlight(at: loc)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        clearDropTargetHighlight()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        clearDropTargetHighlight()
        let locScreen = convert(sender.draggingLocation, from: nil)
        let urls = extractFileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        let paths = urls.map { $0.path }

        // 检查是否落在某个节点上
        if let targetNodeId = nodeId(at: locScreen) {
            onFilesDroppedOnNode?(paths, targetNodeId)
            return true
        }

        // 落在空白区域：所有文件都创建 Note 节点
        let locCanvas = screenToCanvas(locScreen)
        if !paths.isEmpty {
            onFilesDropped?(paths, locCanvas)
        }
        return true
    }

    /// 查找指定屏幕坐标下的节点 ID（使用 hitTestCanvas，兼容 NSHostingView 迁移后 nodeViews 为空的情况）
    func nodeId(at screenPoint: CGPoint) -> UUID? {
        let hit = hitTestCanvas(at: screenPoint)
        switch hit {
        case .nodeHeader(let id), .nodeFooter(let id), .nodeContent(let id, _), .nodeResize(let id, _):
            return id
        case .canvas:
            return nil
        }
    }

    /// 拖拽悬停时高亮目标节点（通过 NotificationCenter 更新 SwiftUI 层 dropTargetNodeId）
    private func updateDropTargetHighlight(at screenPoint: CGPoint) {
        let newTarget = nodeId(at: screenPoint)
        if newTarget != dropTargetNodeId {
            dropTargetNodeId = newTarget
            NotificationCenter.default.post(
                name: .canvasDropTargetChanged,
                object: nil,
                userInfo: ["dropTargetNodeId": newTarget as Any]
            )
        }
    }

    private func clearDropTargetHighlight() {
        dropTargetNodeId = nil
        NotificationCenter.default.post(
            name: .canvasDropTargetChanged,
            object: nil,
            userInfo: [:]
        )
    }

    private func containsFileURLs(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        return !urls.isEmpty
    }

    private func extractFileURLs(from sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
    }

    private func isMarkdownPath(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "md" || ext == "markdown" || ext == "txt"
    }
}
