import AppKit

extension CanvasViewportView {

    // MARK: - 节点拖动（画布层统一处理，避免 layout() 干扰）

    /// 由 BaseNodeView.mouseDown 调用，初始化画布层节点拖动
    func beginNodeDrag(nodeId: UUID?, screenLoc: CGPoint) {
        guard let nodeId else { return }

        // 防止重复初始化：如果已经在拖动同一个节点，忽略重复调用
        if draggingNodeId == nodeId {
            return
        }

        draggingNodeId = nodeId
        dragStartCanvasMouse = screenToCanvas(screenLoc)
        dragStartCanvasFrame = nodeCanvasFrames[nodeId]
        lastSnapActive = false
        lastSnappedGridOrigin = nil
        didDragMove = false

        // 批量拖动：如果被拖动节点在选中集合中且选中集合 > 1，记录所有选中节点的初始 frame
        batchDragStartFrames.removeAll()
        if selectedNodeIds.contains(nodeId) && selectedNodeIds.count > 1 {
            for id in selectedNodeIds {
                if let frame = nodeCanvasFrames[id] {
                    batchDragStartFrames[id] = frame
                }
            }
        }
    }

    // MARK: - 鼠标点击（选择节点）

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let hit = hitTest(loc)

        // Space+点击 进入平移拖拽
        if isSpaceHeld {
            spaceDragStartOrigin = canvasOrigin
            spaceDragStartMouse = loc
            NSCursor.closedHand.set()
            return
        }

        // 连线模式（isInConnectingMode）：点击节点建立连接，点击空白取消
        if isInConnectingMode {
            if let nodeId = nodeId(for: hit) {
                handleConnectionClick(nodeId: nodeId)
            } else {
                // 点击空白取消连线
                deactivateConnectionMode()
            }
            return
        }

        // 有起点时的遗留处理（兼容程序触发的连线）
        if connectingFromNodeId != nil {
            if let nodeId = nodeId(for: hit) {
                handleConnectionClick(nodeId: nodeId)
                return
            } else {
                connectingFromNodeId = nil
                connectionDragPoint = nil
                needsDisplay = true
                return
            }
        }

        // 节点绘制模式：在空白处（非节点区域）点击/拖拽创建节点
        if isInDrawingMode && nodeId(for: hit) == nil {
            drawingStartPoint = loc
            return
        }

        // 节点选中由 BaseNodeView.onNodeClicked 回调处理；
        // canvas mouseDown 只负责点击空白区域的清除选中 + 框选初始化
        if nodeId(for: hit) == nil {
            if !event.modifierFlags.contains(.command) {
                selectedNodeIds.removeAll()
            }
            window?.makeFirstResponder(self)
            // 在选择模式下（非绘制、非连线），空白区域按下时初始化框选
            if !isInDrawingMode && !isInConnectingMode {
                selectionStartPoint = loc
                selectionCurrentPoint = nil
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if connectingFromNodeId != nil {
            connectionDragPoint = convert(event.locationInWindow, from: nil)
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        // Space+拖拽平移
        if isSpaceHeld, let startOrigin = spaceDragStartOrigin, let startMouse = spaceDragStartMouse {
            let dx = (loc.x - startMouse.x) / zoom
            let dy = (loc.y - startMouse.y) / zoom
            canvasOrigin = CGPoint(x: startOrigin.x - dx, y: startOrigin.y - dy)
            needsLayout = true
            notifyViewportChanged()
            return
        }

        // 节点绘制模式拖拽
        if isInDrawingMode, drawingStartPoint != nil {
            drawingCurrentPoint = loc
            needsDisplay = true
            return
        }

        if connectingFromNodeId != nil {
            connectionDragPoint = loc
            needsDisplay = true
            return
        }

        // 框选拖拽（选择模式下空白区域拖拽）：只更新绘制坐标，不修改选中状态
        if selectionStartPoint != nil {
            selectionCurrentPoint = loc
            needsDisplay = true
            return
        }

        // 节点拖动（画布层统一处理）
        if let nodeId = draggingNodeId,
           let startMouse = dragStartCanvasMouse,
           let startFrame = dragStartCanvasFrame,
           let view = nodeViews[nodeId] {

            didDragMove = true
            let currentCanvas = screenToCanvas(loc)
            let rawDX = currentCanvas.x - startMouse.x
            let rawDY = currentCanvas.y - startMouse.y
            var newOrigin = CGPoint(
                x: startFrame.origin.x + rawDX,
                y: startFrame.origin.y + rawDY
            )
            var newFrame = CGRect(origin: newOrigin, size: startFrame.size)

            // 批量拖动时，吸附计算排除所有被拖动的节点
            let draggedIds = isBatchDragging ? Set(batchDragStartFrames.keys) : [nodeId]

            if event.modifierFlags.contains(.command) {
                // ⌘+拖拽：磁力瓦片对齐（吸附到相邻节点边缘）
                let otherFrames = nodeCanvasFrames
                    .filter { !draggedIds.contains($0.key) }
                    .map { $0.value }
                let (snapped, guidelines) = TileSnapping.snap(
                    draggingFrame: newFrame,
                    against: otherFrames
                )
                let snapActive = snapped != newOrigin
                newOrigin = snapped
                newFrame = CGRect(origin: newOrigin, size: startFrame.size)
                dragGuidelines = guidelines
                if snapActive && !lastSnapActive {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                lastSnapActive = snapActive
            } else {
                // 普通拖拽：先尝试吸附到相邻节点边缘，无相邻节点则回落到 16px 网格
                let otherFrames = nodeCanvasFrames
                    .filter { !draggedIds.contains($0.key) }
                    .map { $0.value }
                let (nodeSnapped, guidelines) = TileSnapping.snap(
                    draggingFrame: newFrame,
                    against: otherFrames
                )
                let nodeSnapActive = nodeSnapped != newOrigin
                if nodeSnapActive {
                    newOrigin = nodeSnapped
                    dragGuidelines = guidelines
                    if !lastSnapActive {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                    lastSnapActive = true
                } else {
                    dragGuidelines = []
                    let gridSnapped = snapToGrid(newOrigin, size: startFrame.size)
                    let gridChanged = gridSnapped != lastSnappedGridOrigin
                    newOrigin = gridSnapped
                    if gridChanged && lastSnappedGridOrigin != nil {
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    }
                    lastSnappedGridOrigin = gridSnapped
                    lastSnapActive = false
                }
                newFrame = CGRect(origin: newOrigin, size: startFrame.size)
            }

            // 计算主节点最终位移量（含吸附修正）
            let finalDX = newFrame.origin.x - startFrame.origin.x
            let finalDY = newFrame.origin.y - startFrame.origin.y

            // 直接更新屏幕 frame 和画布坐标缓存（禁用隐式动画，不触发 layout()）
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.frame = canvasRectToScreen(newFrame)
            view.setBoundsSize(newFrame.size)
            nodeCanvasFrames[nodeId] = newFrame

            // 批量拖动：将相同位移应用到所有其他选中节点
            if isBatchDragging {
                for (otherId, otherStartFrame) in batchDragStartFrames where otherId != nodeId {
                    guard let otherView = nodeViews[otherId] else { continue }
                    let otherNewOrigin = CGPoint(
                        x: otherStartFrame.origin.x + finalDX,
                        y: otherStartFrame.origin.y + finalDY
                    )
                    let otherNewFrame = CGRect(origin: otherNewOrigin, size: otherStartFrame.size)
                    otherView.frame = canvasRectToScreen(otherNewFrame)
                    otherView.setBoundsSize(otherNewFrame.size)
                    nodeCanvasFrames[otherId] = otherNewFrame
                }
            }

            CATransaction.commit()
        }
    }

    /// 将节点 frame 的四条边吸附到背景网格线（与 drawLineGrid 使用的坐标系一致）
    /// 分别对 left/right/top/bottom 四边取整，选择位移量最小的那条边对齐
    private func snapToGrid(_ origin: CGPoint, size: CGSize) -> CGPoint {
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

    override func mouseUp(with event: NSEvent) {
        // 框选结束：计算选中节点，然后清除框选状态
        if selectionStartPoint != nil {
            if let rect = selectionRect, rect.width > 4 || rect.height > 4 {
                var hitIds = Set<UUID>()
                for (id, view) in nodeViews {
                    if view.frame.intersects(rect) {
                        hitIds.insert(id)
                    }
                }
                selectedNodeIds = hitIds
            }
            selectionStartPoint = nil
            selectionCurrentPoint = nil
            needsDisplay = true
        }

        // Space+拖拽结束
        if isSpaceHeld {
            spaceDragStartOrigin = nil
            spaceDragStartMouse = nil
            NSCursor.openHand.set()
        }

        // 节点拖动结束：持久化最终 canvas frame
        if let nodeId = draggingNodeId {
            dragGuidelines = []
            if didDragMove {
                if isBatchDragging {
                    // 批量拖动结束：收集所有被拖动节点的最终 frame 并统一持久化
                    var finalFrames: [UUID: CGRect] = [:]
                    for id in batchDragStartFrames.keys {
                        if let frame = nodeCanvasFrames[id] {
                            finalFrames[id] = frame
                        }
                    }
                    onBatchNodeDragEnded?(finalFrames)
                } else if let finalFrame = nodeCanvasFrames[nodeId] {
                    onNodeDragEnded?(nodeId, finalFrame)
                }
            } else {
                // 没有发生拖动 = 单击：如果之前是多选且点击的节点在选中集合中，执行单选
                if selectedNodeIds.count > 1 && selectedNodeIds.contains(nodeId) {
                    selectedNodeIds = [nodeId]
                }
            }
        }
        draggingNodeId = nil
        dragStartCanvasMouse = nil
        dragStartCanvasFrame = nil
        batchDragStartFrames.removeAll()
        didDragMove = false
        lastSnapActive = false
        lastSnappedGridOrigin = nil

        // 节点绘制模式完成
        if isInDrawingMode, let start = drawingStartPoint {
            let current = drawingCurrentPoint ?? start
            let rect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )

            if rect.width > 20 && rect.height > 20 {
                // 拖拽绘制：使用用户绘制的尺寸
                let canvasRect = CGRect(
                    origin: screenToCanvas(rect.origin),
                    size: CGSize(width: rect.width / zoom, height: rect.height / zoom)
                )
                onNodeDrawn?(drawingNodeType, canvasRect)
            } else {
                // 点击创建：使用默认尺寸，以点击位置为中心
                let defaultSize = defaultNodeSize(for: drawingNodeType)
                let canvasPoint = screenToCanvas(start)
                let canvasRect = CGRect(
                    x: canvasPoint.x - defaultSize.width / 2,
                    y: canvasPoint.y - defaultSize.height / 2,
                    width: defaultSize.width,
                    height: defaultSize.height
                )
                onNodeDrawn?(drawingNodeType, canvasRect)
            }

            drawingStartPoint = nil
            drawingCurrentPoint = nil
            needsDisplay = true
            return
        }
    }

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
        guard isInDrawingMode, let start = drawingStartPoint, let current = drawingCurrentPoint else { return }
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
