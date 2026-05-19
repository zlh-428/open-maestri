import AppKit

// MARK: - 画布命中测试结果

/// 语义化命中区域，供 CanvasInteractionHandler 使用
enum CanvasHitTestResult {
    case canvas
    case nodeHeader(UUID)
    case nodeContent(UUID, NSView)
    case nodeResize(UUID, BaseNodeView.ResizeEdge)
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
    case resizingNode(UUID, edge: BaseNodeView.ResizeEdge, startFrame: CGRect, startMouse: CGPoint)
    case marquee(start: CGPoint)
    case panCanvas(startOrigin: CGPoint, startMouse: CGPoint)
    case drawing(start: CGPoint)
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

// MARK: - CanvasViewportView 交互 extension

extension CanvasViewportView {

    // MARK: - 语义化命中测试

    /// 将画布坐标 point 映射到语义化命中区域
    /// 优先级：resize 热区 > header 区域 > 内容区 > 空白
    func hitTestCanvas(at loc: CGPoint) -> CanvasHitTestResult {
        // 按 subviews 逆序遍历（最顶层的 nodeView 优先）
        for view in subviews.reversed() {
            guard let id = viewToNodeId[ObjectIdentifier(view)],
                  view.frame.contains(loc),
                  let base = view as? BaseNodeView else { continue }

            // 将画布坐标转换为节点 bounds 坐标
            // view.frame 是缩放后屏幕坐标，bounds 是原始画布尺寸
            let localX = (loc.x - view.frame.minX) / zoom
            let localY = (loc.y - view.frame.minY) / zoom
            let localPoint = CGPoint(x: localX, y: localY)

            // 1. resize 热区优先
            if let edge = base.resizeEdge(at: localPoint) {
                return .nodeResize(id, edge)
            }

            // 2. header 区域
            let headerH = BaseNodeView.headerHeight
            if localY >= base.bounds.height - headerH {
                return .nodeHeader(id)
            }

            // 3. 内容区：做 deep hitTest 找最深子视图
            // NSScroller 豁免：不拦截，让滚动条自然处理
            let contentLocal = base.contentView.convert(CGPoint(x: localX, y: localY), from: base)
            if let deepHit = base.contentView.hitTest(contentLocal) {
                if deepHit is NSScroller {
                    return .canvas
                }
                return .nodeContent(id, deepHit)
            }

            return .nodeContent(id, base.contentView)
        }

        return .canvas
    }

    // MARK: - 选中逻辑

    /// 根据修饰键更新 selectedNodeIds
    func updateSelection(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selectedNodeIds.contains(id) {
                selectedNodeIds.remove(id)
            } else {
                selectedNodeIds.insert(id)
            }
        } else {
            if !selectedNodeIds.contains(id) {
                selectedNodeIds = [id]
            }
            // 如果节点已在选中集合内（批量选中状态），mouseUp 时再收窄
        }
    }

    // MARK: - 统一鼠标事件处理

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        // 1. Space+点击 → 平移模式
        if isSpaceHeld {
            interaction = .panCanvas(startOrigin: canvasOrigin, startMouse: loc)
            NSCursor.closedHand.set()
            return
        }

        // 2. 连线模式：点击节点建立连接，点击空白取消
        if isInConnectingMode {
            let hit = hitTestCanvas(at: loc)
            if case .nodeHeader(let id) = hit {
                handleConnectionClick(nodeId: id)
            } else if case .nodeContent(let id, _) = hit {
                handleConnectionClick(nodeId: id)
            } else {
                deactivateConnectionMode()
            }
            return
        }

        // 兼容：程序触发的连线起点
        if connectingFromNodeId != nil {
            let hit = hitTestCanvas(at: loc)
            if case .nodeHeader(let id) = hit {
                handleConnectionClick(nodeId: id)
                return
            } else if case .nodeContent(let id, _) = hit {
                handleConnectionClick(nodeId: id)
                return
            } else {
                connectingFromNodeId = nil
                connectionDragPoint = nil
                needsDisplay = true
                return
            }
        }

        // 3. 节点绘制模式：空白区域开始绘制
        if isInDrawingMode {
            let hit = hitTestCanvas(at: loc)
            if case .canvas = hit {
                interaction = .drawing(start: loc)
                return
            }
            // 绘制模式下点击节点 → fall through 正常走节点交互
        }

        // 4. 语义化命中测试 → 分发
        let hit = hitTestCanvas(at: loc)
        switch hit {
        case .canvas:
            if !event.modifierFlags.contains(.command) {
                selectedNodeIds.removeAll()
            }
            window?.makeFirstResponder(self)
            interaction = .marquee(start: loc)
            marqueeCurrentPoint = nil

        case .nodeHeader(let id):
            guard let base = nodeViews[id] as? BaseNodeView, !base.isLocked else { return }
            updateSelection(id, modifiers: event.modifierFlags)
            base.onActivated?()
            let startFrame = nodeCanvasFrames[id] ?? .zero
            interaction = .mayDragNode(id, startMouse: loc, startFrame: startFrame, contentTarget: nil)

        case .nodeContent(let id, let deepHit):
            guard let base = nodeViews[id] as? BaseNodeView, !base.isLocked else { return }
            updateSelection(id, modifiers: event.modifierFlags)
            base.onActivated?()
            // 立即将 mouseDown 透传给内容区目标（Terminal 获焦等）
            deepHit.mouseDown(with: event)
            let startFrame = nodeCanvasFrames[id] ?? .zero
            interaction = .mayDragNode(id, startMouse: loc, startFrame: startFrame, contentTarget: deepHit)

        case .nodeResize(let id, let edge):
            guard let base = nodeViews[id] as? BaseNodeView, !base.isLocked else { return }
            updateSelection(id, modifiers: event.modifierFlags)
            base.onActivated?()
            let startFrame = nodeCanvasFrames[id] ?? .zero
            interaction = .resizingNode(id, edge: edge, startFrame: startFrame, startMouse: loc)
            edge.cursor.set()
        }
    }

    // MARK: - 拖动处理

    private static let dragThreshold: CGFloat = 3.0

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        switch interaction {

        // --- 画布平移 ---
        case .panCanvas(let startOrigin, let startMouse):
            let dx = (loc.x - startMouse.x) / zoom
            let dy = (loc.y - startMouse.y) / zoom
            canvasOrigin = CGPoint(x: startOrigin.x - dx, y: startOrigin.y - dy)
            needsLayout = true
            notifyViewportChanged()

        // --- 等待判断（点击 or 拖动）---
        case .mayDragNode(let id, let startMouse, let startFrame, let contentTarget):
            let dx = loc.x - startMouse.x
            let dy = loc.y - startMouse.y
            let dist = sqrt(dx * dx + dy * dy)
            guard dist >= Self.dragThreshold else { return }
            // 安全检查：必须有物理左键按下，防止触控板双指滚动误触
            guard NSEvent.pressedMouseButtons & 1 != 0 else { return }

            // Option+拖动 → 触发节点复制而非移动
            if event.modifierFlags.contains(.option),
               let base = nodeViews[id] as? BaseNodeView {
                interaction = .idle
                base.onDuplicate?()
                return
            }

            // 若已透传 mouseDown 给内容区，发合成 mouseUp 取消其内部状态
            if let target = contentTarget {
                if let cancelEvent = NSEvent.mouseEvent(
                    with: .leftMouseUp,
                    location: event.locationInWindow,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: event.windowNumber,
                    context: nil,
                    eventNumber: event.eventNumber,
                    clickCount: 1,
                    pressure: 0
                ) {
                    target.mouseUp(with: cancelEvent)
                }
            }

            // 切换为真正拖动
            let canvasMouse = screenToCanvas(startMouse)
            if selectedNodeIds.count > 1 && selectedNodeIds.contains(id) {
                var startFrames: [UUID: CGRect] = [:]
                for sid in selectedNodeIds {
                    startFrames[sid] = nodeCanvasFrames[sid] ?? .zero
                }
                interaction = .batchDragging(startFrames, primaryId: id, startMouse: canvasMouse)
            } else {
                interaction = .draggingNode(id, startMouse: canvasMouse, startFrame: startFrame)
            }
            // 立即处理第一帧拖动（递归调用）
            mouseDragged(with: event)

        // --- 单节点拖动 ---
        case .draggingNode(let id, let startMouse, let startFrame):
            guard let view = nodeViews[id] else { return }
            let currentCanvas = screenToCanvas(loc)
            let rawDX = currentCanvas.x - startMouse.x
            let rawDY = currentCanvas.y - startMouse.y
            var newOrigin = CGPoint(x: startFrame.origin.x + rawDX, y: startFrame.origin.y + rawDY)
            var newFrame = CGRect(origin: newOrigin, size: startFrame.size)

            let otherFrames = nodeCanvasFrames.filter { $0.key != id }.map { $0.value }
            if event.modifierFlags.contains(.command) {
                let (snapped, guidelines) = TileSnapping.snap(draggingFrame: newFrame, against: otherFrames)
                let snapActive = snapped != newOrigin
                newOrigin = snapped
                newFrame = CGRect(origin: newOrigin, size: startFrame.size)
                dragGuidelines = guidelines
                if snapActive && !lastSnapActive {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                lastSnapActive = snapActive
            } else {
                let (nodeSnapped, guidelines) = TileSnapping.snap(draggingFrame: newFrame, against: otherFrames)
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

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.frame = canvasRectToScreen(newFrame)
            view.setBoundsSize(newFrame.size)
            nodeCanvasFrames[id] = newFrame
            CATransaction.commit()

        // --- 批量拖动 ---
        case .batchDragging(let startFrames, let primaryId, let startMouse):
            let currentCanvas = screenToCanvas(loc)
            let rawDX = currentCanvas.x - startMouse.x
            let rawDY = currentCanvas.y - startMouse.y

            guard let primaryStart = startFrames[primaryId] else { return }
            let primaryRaw = CGRect(
                origin: CGPoint(x: primaryStart.origin.x + rawDX, y: primaryStart.origin.y + rawDY),
                size: primaryStart.size
            )
            let otherFrames = nodeCanvasFrames.filter { !startFrames.keys.contains($0.key) }.map { $0.value }
            let (snapped, guidelines) = TileSnapping.snap(draggingFrame: primaryRaw, against: otherFrames)
            let finalDX = snapped.x - primaryStart.origin.x
            let finalDY = snapped.y - primaryStart.origin.y
            dragGuidelines = guidelines
            let snapActive = snapped != primaryRaw.origin
            if snapActive && !lastSnapActive {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            lastSnapActive = snapActive

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (sid, sFrame) in startFrames {
                guard let sView = nodeViews[sid] else { continue }
                let newOrigin = CGPoint(x: sFrame.origin.x + finalDX, y: sFrame.origin.y + finalDY)
                let newFrame = CGRect(origin: newOrigin, size: sFrame.size)
                sView.frame = canvasRectToScreen(newFrame)
                sView.setBoundsSize(newFrame.size)
                nodeCanvasFrames[sid] = newFrame
            }
            CATransaction.commit()

        // --- Resize ---
        case .resizingNode(let id, let edge, let startFrame, let startMouse):
            guard let view = nodeViews[id] as? BaseNodeView else { return }
            let dx = loc.x - startMouse.x
            let dy = loc.y - startMouse.y
            applyResizeOnCanvas(id: id, view: view, edge: edge, dx: dx, dy: dy, startFrame: startFrame)

        // --- 框选 ---
        case .marquee:
            marqueeCurrentPoint = loc
            needsDisplay = true

        // --- 节点绘制模式 ---
        case .drawing:
            drawingCurrentPoint = loc
            needsDisplay = true

        // --- idle（连线工具跟踪）---
        case .idle:
            if connectingFromNodeId != nil {
                connectionDragPoint = loc
                needsDisplay = true
            }
        }
    }

    // MARK: - Resize 辅助

    private func applyResizeOnCanvas(id: UUID, view: BaseNodeView,
                                      edge: BaseNodeView.ResizeEdge,
                                      dx: CGFloat, dy: CGFloat,
                                      startFrame: CGRect) {
        let minW = BaseNodeView.minNodeWidth * zoom
        let minH = BaseNodeView.minNodeHeight * zoom

        var x = startFrame.origin.x
        var y = startFrame.origin.y
        var w = startFrame.width
        var h = startFrame.height

        // startFrame 是屏幕坐标（缩放后），dx/dy 亦为屏幕坐标
        // isFlipped = false：y=0 在底部，dy>0 向上
        switch edge {
        case .right:
            w = max(w + dx, minW)
        case .left:
            let newW = max(w - dx, minW)
            x = startFrame.maxX - newW
            w = newW
        case .bottom:
            let top = y + h
            let newH = max(h - dy, minH)
            y = top - newH
            h = newH
        case .top:
            h = max(h + dy, minH)
        case .bottomLeft:
            let newW = max(w - dx, minW)
            x = startFrame.maxX - newW
            w = newW
            let top = y + h
            let newH = max(h - dy, minH)
            y = top - newH
            h = newH
        case .bottomRight:
            w = max(w + dx, minW)
            let top = y + h
            let newH = max(h - dy, minH)
            y = top - newH
            h = newH
        case .topLeft:
            let newW = max(w - dx, minW)
            x = startFrame.maxX - newW
            w = newW
            h = max(h + dy, minH)
        case .topRight:
            w = max(w + dx, minW)
            h = max(h + dy, minH)
        }

        let newScreenFrame = CGRect(x: x, y: y, width: w, height: h)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.frame = newScreenFrame
        view.setBoundsSize(CGSize(width: w / zoom, height: h / zoom))
        let canvasOriginPt = screenToCanvas(newScreenFrame.origin)
        nodeCanvasFrames[id] = CGRect(x: canvasOriginPt.x, y: canvasOriginPt.y,
                                       width: w / zoom, height: h / zoom)
        CATransaction.commit()

        if view.isNodeSelected { view.needsLayout = true }
    }

    // MARK: - mouseUp

    override func mouseUp(with event: NSEvent) {
        defer {
            interaction = .idle
            lastSnapActive = false
            lastSnappedGridOrigin = nil
        }

        switch interaction {

        case .mayDragNode(let id, _, _, let contentTarget):
            // 没有发生拖动 = 点击
            if let target = contentTarget {
                // mouseDown 已透传，补发 mouseUp 完成点击序列
                target.mouseUp(with: event)
            }
            // 单击已在多选集合中的节点 → 收窄为单选
            if selectedNodeIds.count > 1 && selectedNodeIds.contains(id) {
                selectedNodeIds = [id]
            }

        case .draggingNode(let id, _, _):
            dragGuidelines = []
            if let finalFrame = nodeCanvasFrames[id] {
                onNodeDragEnded?(id, finalFrame)
            }

        case .batchDragging(let startFrames, _, _):
            dragGuidelines = []
            var finalFrames: [UUID: CGRect] = [:]
            for id in startFrames.keys {
                if let f = nodeCanvasFrames[id] { finalFrames[id] = f }
            }
            onBatchNodeDragEnded?(finalFrames)

        case .resizingNode(let id, _, _, _):
            NSCursor.arrow.set()
            if let finalFrame = nodeCanvasFrames[id] {
                onNodeResizeEnded?(id, finalFrame)
            }

        case .marquee(let start):
            if let current = marqueeCurrentPoint {
                let rect = CGRect(
                    x: min(start.x, current.x),
                    y: min(start.y, current.y),
                    width: abs(current.x - start.x),
                    height: abs(current.y - start.y)
                )
                if rect.width > 4 || rect.height > 4 {
                    var hitIds = Set<UUID>()
                    for (id, view) in nodeViews {
                        if view.frame.intersects(rect) { hitIds.insert(id) }
                    }
                    selectedNodeIds = hitIds
                }
            }
            marqueeCurrentPoint = nil
            needsDisplay = true

        case .drawing(let start):
            let current = drawingCurrentPoint ?? start
            let rect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            if rect.width > 20 && rect.height > 20 {
                let canvasRect = CGRect(
                    origin: screenToCanvas(rect.origin),
                    size: CGSize(width: rect.width / zoom, height: rect.height / zoom)
                )
                onNodeDrawn?(drawingNodeType, canvasRect)
            } else {
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
            drawingCurrentPoint = nil
            needsDisplay = true

        case .panCanvas:
            if isSpaceHeld { NSCursor.openHand.set() } else { NSCursor.arrow.set() }

        case .idle:
            break
        }
    }

    // MARK: - mouseMoved

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        // 连线工具：跟踪鼠标位置
        if connectingFromNodeId != nil {
            connectionDragPoint = loc
            needsDisplay = true
        }

        // 光标：根据命中区域设置
        if isSpaceHeld {
            NSCursor.openHand.set()
            return
        }
        switch hitTestCanvas(at: loc) {
        case .nodeResize(_, let edge):
            edge.cursor.set()
        case .nodeHeader, .nodeContent, .canvas:
            NSCursor.arrow.set()
        }
    }
}
