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
            options: [.activeInKeyWindow, .mouseMoved],
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

    // MARK: - 磁力对齐参考线绘制

    func drawSnapGuidelines() {
        guard !dragGuidelines.isEmpty else { return }
        NSColor.systemBlue.withAlphaComponent(0.7).setStroke()
        for line in dragGuidelines {
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

    // MARK: - 临时连线绘制（连线工具拖动时）

    func drawTemporaryConnection() {
        guard let fromId = connectingFromNodeId,
              let fromView = nodeViews[fromId],
              let toPoint = connectionDragPoint else { return }
        let fromPoint = CGPoint(x: fromView.frame.midX, y: fromView.frame.midY)
        let path = NSBezierPath()
        path.move(to: fromPoint)
        path.line(to: toPoint)
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
        path.stroke()

        // 起点节点高亮
        NSColor.systemBlue.withAlphaComponent(0.3).setFill()
        let dot = NSBezierPath(ovalIn: fromView.frame.insetBy(dx: -3, dy: -3))
        dot.fill()
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

    /// 查找指定屏幕坐标下的节点 ID
    func nodeId(at screenPoint: CGPoint) -> UUID? {
        for (id, view) in nodeViews {
            if view.frame.contains(screenPoint) {
                return id
            }
        }
        return nil
    }

    /// 拖拽悬停时高亮目标节点
    private func updateDropTargetHighlight(at screenPoint: CGPoint) {
        let newTarget = nodeId(at: screenPoint)
        if newTarget != dropTargetNodeId {
            // 清除旧高亮
            if let oldId = dropTargetNodeId, let oldView = nodeViews[oldId] as? BaseNodeView {
                oldView.layer?.borderColor = NSColor(white: 0.85, alpha: 1).cgColor
                oldView.layer?.borderWidth = 0.5
            }
            // 设置新高亮
            if let newId = newTarget, let newView = nodeViews[newId] as? BaseNodeView {
                newView.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.8).cgColor
                newView.layer?.borderWidth = 2
            }
            dropTargetNodeId = newTarget
        }
    }

    private func clearDropTargetHighlight() {
        if let oldId = dropTargetNodeId, let oldView = nodeViews[oldId] as? BaseNodeView {
            oldView.layer?.borderColor = NSColor(white: 0.85, alpha: 1).cgColor
            oldView.layer?.borderWidth = 0.5
        }
        dropTargetNodeId = nil
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
