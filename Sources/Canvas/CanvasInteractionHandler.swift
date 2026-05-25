import AppKit
import WebKit

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

// MARK: - CanvasViewportView 交互 extension

extension CanvasViewportView {

    // MARK: - 语义化命中测试

    /// 将画布坐标 point 映射到语义化命中区域
    /// 优先级：选中节点外扩 resize 热区 > 节点内容区（header/footer/content）> 未选中节点内缩 resize > 空白
    /// 纯几何计算，不依赖 BaseNodeView 或子视图 hitTest（避免无限递归）
    func hitTestCanvas(at loc: CGPoint) -> CanvasHitTestResult {
        // 鼠标位移小于阈值时直接返回缓存结果（避免 60fps 下每帧两次 O(n) 遍历）
        let dx = loc.x - _hitTestCachedPoint.x
        let dy = loc.y - _hitTestCachedPoint.y
        if dx * dx + dy * dy < Self._hitTestReuseThreshold * Self._hitTestReuseThreshold {
            return _hitTestCachedResult
        }

        // Pass 0：shape 节点旋转手柄命中检测（优先级最高）
        for node in sortedNodesByZIndexDesc where selectedNodeIds.contains(node.id) {
            guard case .shape(let sc) = node.content else { continue }
            let screenFrame = canvasRectToScreen(node.frame)
            let nodeCenter = CGPoint(x: screenFrame.midX, y: screenFrame.midY)

            // 旋转手柄在节点顶边中点上方 (lineLength=20 + dotRadius=5) = 25pt（未旋转坐标系）
            let handleOffsetY: CGFloat = 25
            let unrotatedHandleX = screenFrame.midX
            let unrotatedHandleY = screenFrame.minY - handleOffsetY

            // 将手柄位置从节点局部坐标旋转到屏幕坐标
            let dx0 = unrotatedHandleX - nodeCenter.x
            let dy0 = unrotatedHandleY - nodeCenter.y
            let cosA = cos(sc.rotation)
            let sinA = sin(sc.rotation)
            let rotatedX = nodeCenter.x + dx0 * cosA - dy0 * sinA
            let rotatedY = nodeCenter.y + dx0 * sinA + dy0 * cosA

            let handleCenter = CGPoint(x: rotatedX, y: rotatedY)
            let halo: CGFloat = 12
            let distSq = (loc.x - handleCenter.x) * (loc.x - handleCenter.x) +
                         (loc.y - handleCenter.y) * (loc.y - handleCenter.y)
            if distSq <= halo * halo {
                let r = CanvasHitTestResult.nodeRotateHandle(node.id)
                _hitTestCachedPoint = loc; _hitTestCachedResult = r
                return r
            }
        }

        // Pass 1：对已选中节点先检测外扩 resize 热区（在节点边框外侧，不与内容冲突）
        for node in sortedNodesByZIndexDesc where selectedNodeIds.contains(node.id) {
            guard !isNodeLocked(node.id) else { continue }
            // text/drawing 节点不支持 resize，尺寸由内容自适应
            if case .text    = node.content { continue }
            if case .shape(let sc) = node.content, sc.rotation != 0 { continue }
            let screenFrame = canvasRectToScreen(node.frame)
            // 外扩热区：以 selectionOutset + resizeHaloWidth 向外膨胀
            let halo = Self.resizeHaloWidth
            let expandedFrame = screenFrame.insetBy(dx: -halo, dy: -halo)
            guard expandedFrame.contains(loc) && !screenFrame.insetBy(dx: Self.resizeInnerDeadZone, dy: Self.resizeInnerDeadZone).contains(loc) else { continue }
            let localPt = CGPoint(x: loc.x - screenFrame.minX, y: loc.y - screenFrame.minY)
            if let edge = outerResizeEdge(at: localPt, nodeSize: screenFrame.size, halo: halo) {
                let r = CanvasHitTestResult.nodeResize(node.id, edge)
                _hitTestCachedPoint = loc; _hitTestCachedResult = r
                return r
            }
        }

        // Pass 2：正常节点内部命中测试
        for node in sortedNodesByZIndexDesc {
            let screenFrame = canvasRectToScreen(node.frame)
            guard screenFrame.contains(loc) else { continue }

            let localPt = CGPoint(
                x: loc.x - screenFrame.minX,
                y: loc.y - screenFrame.minY
            )

            // header 在节点顶部（y 向下：minY 是顶边，localPt.y 小 = 顶部）
            let scaledHeaderHeight = CanvasNodeConstants.headerHeight * zoom
            if localPt.y <= scaledHeaderHeight {
                let r = CanvasHitTestResult.nodeHeader(node.id)
                _hitTestCachedPoint = loc; _hitTestCachedResult = r
                return r
            }

            // footer 在节点底部（仅终端节点有 footer）
            if case .terminal = node.content {
                let scaledFooterHeight = CanvasNodeConstants.footerHeight * zoom
                if localPt.y >= screenFrame.height - scaledFooterHeight {
                    let r = CanvasHitTestResult.nodeFooter(node.id)
                    _hitTestCachedPoint = loc; _hitTestCachedResult = r
                    return r
                }
            }

            let r = CanvasHitTestResult.nodeContent(node.id, nodesHostingView ?? self)
            _hitTestCachedPoint = loc; _hitTestCachedResult = r
            return r
        }
        let r = CanvasHitTestResult.canvas
        _hitTestCachedPoint = loc; _hitTestCachedResult = r
        return r
    }

    // MARK: - Resize 热区常量

    /// 外扩 resize 热区总宽度（屏幕像素，不受 zoom 影响）
    /// 蓝色虚线框距节点边缘 selectionOutset(3pt)，热区再向内延伸到此宽度
    private static let resizeHaloWidth: CGFloat = 10
    /// 节点内部死区：在此范围内的点击不触发外扩 resize，直接进入内容区交互
    private static let resizeInnerDeadZone: CGFloat = 0

    /// 外扩模式：热区在节点边缘 [-halo, +halo] 范围内（以节点 screenFrame 为基准，localPt 允许负值）
    /// 角点优先，其次四边；仅在靠近边缘的条带内响应
    private func outerResizeEdge(at localPt: CGPoint, nodeSize: CGSize, halo: CGFloat) -> ResizeEdge? {
        let w = nodeSize.width
        let h = nodeSize.height
        guard w > halo * 4 && h > halo * 4 else { return nil }

        // 热区条带：距各边缘 halo 范围内（localPt 相对 screenFrame.origin，可为负）
        let nearLeft   = localPt.x < halo
        let nearRight  = localPt.x > w - halo
        let nearTop    = localPt.y < halo
        let nearBottom = localPt.y > h - halo

        // 至少靠近一条边才响应
        guard nearLeft || nearRight || nearTop || nearBottom else { return nil }

        if nearTop    && nearLeft  { return .topLeft }
        if nearTop    && nearRight { return .topRight }
        if nearBottom && nearLeft  { return .bottomLeft }
        if nearBottom && nearRight { return .bottomRight }
        if nearLeft                { return .left }
        if nearRight               { return .right }
        if nearTop                 { return .top }
        if nearBottom              { return .bottom }
        return nil
    }

    // MARK: - 节点锁定查询

    private func isNodeLocked(_ id: UUID) -> Bool {
        currentNodes.first(where: { $0.id == id })?.isLocked ?? false
    }

    // MARK: - 选中逻辑

    /// 根据修饰键更新 selectedNodeIds，并将选中节点提升到最高层
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
        // 将选中的节点提升到最高层级，确保重叠时操作正确
        bringNodesToFront([id])
    }

    /// fileTree 内容区点击时由 CanvasNodesView 主动调用，触发节点选中流程
    /// （内容区事件被 NSOutlineView/NSCollectionView 消费，不会到达 CanvasInteractionHandler.mouseDown）
    func selectFileTreeNode(at loc: CGPoint, modifiers: NSEvent.ModifierFlags) {
        let hit = hitTestCanvas(at: loc)
        switch hit {
        case .nodeContent(let id, _), .nodeHeader(let id), .nodeFooter(let id):
            // 连线模式下点击不可连接节点：取消连线模式，保留原选中状态
            if isInConnectingMode || connectingFromNodeId != nil {
                let isConnectable = currentNodes.first(where: { $0.id == id })?.content.isConnectable ?? true
                if !isConnectable {
                    isInConnectingMode = false
                    return
                }
            }
            updateSelection(id, modifiers: modifiers)
            NotificationCenter.default.post(
                name: .canvasNodeActivated,
                object: nil,
                userInfo: ["nodeId": id]
            )
        case .nodeResize, .nodeRotateHandle, .canvas:
            break
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
            } else if case .nodeFooter(let id) = hit {
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
            } else if case .nodeFooter(let id) = hit {
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
                if isStrokeDrawing {
                    interaction = .drawingStroke(start: loc)
                } else if isFreehandDrawing {
                    interaction = .drawingFreehand(points: [loc])
                } else {
                    interaction = .drawing(start: loc)
                }
                drawingLastSnappedRect = nil
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

        case .nodeHeader(let id), .nodeFooter(let id):
            guard !isNodeLocked(id) else { return }
            updateSelection(id, modifiers: event.modifierFlags)
            let startFrame = nodeCanvasFrames[id] ?? .zero
            interaction = .mayDragNode(id, startMouse: loc, startFrame: startFrame, contentTarget: nil)

        case .nodeContent(let id, _):
            guard !isNodeLocked(id) else { return }
            let wasAlreadySelected = selectedNodeIds.contains(id)
            updateSelection(id, modifiers: event.modifierFlags)
            // 发送激活通知（聚焦终端等）
            NotificationCenter.default.post(
                name: .canvasNodeActivated,
                object: nil,
                userInfo: ["nodeId": id]
            )
            // shape 节点
            if let node = currentNodes.first(where: { $0.id == id }),
               case .shape = node.content {
                // 已选中时再次点击 → 进入编辑态
                // NSTextView 始终注册在 ShapeTextViewRegistry，直接转发坐标修正后的 mouseDown，
                // 由 NSTextView 自身定位光标（与 Note 节点处理路径完全一致）
                if wasAlreadySelected,
                   let tv = ShapeTextViewRegistry.shared.textView(for: id) {
                    // ShapeTextEditor 始终存在，tv 始终注册，无需等待 SwiftUI 更新。
                    // 1. 先发通知让 SwiftUI 设 isEditing=true（同步触发 @State 变更）
                    NotificationCenter.default.post(
                        name: .shapeNodeShouldBeginEditing,
                        object: nil,
                        userInfo: ["nodeId": id, "selectAll": false]
                    )
                    // 2. 下一 runloop tick：SwiftUI updateNSView 已将 isEditable=true，
                    //    用正确坐标转发 mouseDown 定位光标
                    let correctedLocation = correctedWindowLocationForShapeTextView(for: event, nodeId: id, textView: tv)
                    let capturedEvent = event
                    DispatchQueue.main.async {
                        tv.window?.makeFirstResponder(tv)
                        if let syntheticEvent = NSEvent.mouseEvent(
                            with: .leftMouseDown,
                            location: correctedLocation,
                            modifierFlags: capturedEvent.modifierFlags,
                            timestamp: capturedEvent.timestamp,
                            windowNumber: capturedEvent.windowNumber,
                            context: nil,
                            eventNumber: capturedEvent.eventNumber,
                            clickCount: capturedEvent.clickCount,
                            pressure: capturedEvent.pressure
                        ) {
                            tv.mouseDown(with: syntheticEvent)
                        }
                    }
                    return
                }
                // 未选中或无 NSTextView：走普通 mayDragNode
                let startFrame = nodeCanvasFrames[id] ?? .zero
                interaction = .mayDragNode(id, startMouse: loc, startFrame: startFrame, contentTarget: nil)
                return
            }
            // 如果节点已经处于选中状态，将鼠标事件路由给终端视图（支持文字选中）
            if wasAlreadySelected,
               let provider = TerminalManager.shared.providers[id],
               let terminalView = provider.terminalView {
                interaction = .contentInteraction(id, contentTarget: terminalView)
                // 坐标修正：SwiftUI 的 .scaleEffect(zoom) 通过 CALayer transform 缩放节点，
                // 但 NSView.convert(_:from:) 不考虑 layer transform，导致 SwiftTerm 的
                // calculateMouseHit 计算出错误的行列位置。
                // 修正方案：自行计算终端视图内部的正确本地坐标，然后合成一个
                // 让 SwiftTerm convert 能得到正确结果的 locationInWindow。
                let correctedLocation = correctedWindowLocation(for: event, nodeId: id, terminalView: terminalView)
                if let syntheticEvent = NSEvent.mouseEvent(
                    with: .leftMouseDown,
                    location: correctedLocation,
                    modifierFlags: event.modifierFlags,
                    timestamp: event.timestamp,
                    windowNumber: event.windowNumber,
                    context: nil,
                    eventNumber: event.eventNumber,
                    clickCount: event.clickCount,
                    pressure: event.pressure
                ) {
                    terminalView.mouseDown(with: syntheticEvent)
                }
                window?.makeFirstResponder(terminalView)
            }
            // Note 节点：将 NSTextView 设为 first responder 并发送坐标修正的 mouseDown。
            // 不使用 contentInteraction，让 AppKit 原生响应链处理后续 drag/up 事件，
            // 避免在 mouseDragged 中手动转发造成递归崩溃。
            if let node = currentNodes.first(where: { $0.id == id }),
               case .stickyNote = node.content,
               let tv = NoteTextViewRegistry.shared.textView(for: id) {
                window?.makeFirstResponder(tv)
                let correctedLocation = correctedWindowLocationForTextView(for: event, nodeId: id, textView: tv)
                if let syntheticEvent = NSEvent.mouseEvent(
                    with: .leftMouseDown,
                    location: correctedLocation,
                    modifierFlags: event.modifierFlags,
                    timestamp: event.timestamp,
                    windowNumber: event.windowNumber,
                    context: nil,
                    eventNumber: event.eventNumber,
                    clickCount: event.clickCount,
                    pressure: event.pressure
                ) {
                    tv.mouseDown(with: syntheticEvent)
                }
                // interaction 保持 idle，后续 drag/up 由 AppKit 响应链直接路由给 NSTextView
            }
            // Portal 节点：根据点击位置决定聚焦 URL 输入框还是 WebView
            if let node = currentNodes.first(where: { $0.id == id }),
               case .portal = node.content {
                let screenFrame = canvasRectToScreen(node.frame)
                let localY = loc.y - screenFrame.minY
                // 导航栏区域（header 之后约 40px * zoom）
                let navBarBottom = (CanvasNodeConstants.headerHeight + 40) * zoom
                if localY <= navBarBottom,
                   let urlField = PortalWebViewStore.shared.urlTextField(for: id) {
                    window?.makeFirstResponder(urlField)
                } else if let webView = PortalWebViewStore.shared.webView(for: id) {
                    // WebView 区域：第一次点击即路由给 WKWebView（无需先选中再二次点击）
                    interaction = .contentInteraction(id, contentTarget: webView)
                    let correctedLocation = correctedWindowLocationForWebView(for: event, nodeId: id, webView: webView)
                    if let syntheticEvent = NSEvent.mouseEvent(
                        with: .leftMouseDown,
                        location: correctedLocation,
                        modifierFlags: event.modifierFlags,
                        timestamp: event.timestamp,
                        windowNumber: event.windowNumber,
                        context: nil,
                        eventNumber: event.eventNumber,
                        clickCount: event.clickCount,
                        pressure: event.pressure
                    ) {
                        webView.mouseDown(with: syntheticEvent)
                    }
                    window?.makeFirstResponder(webView)
                }
            }
            // 内容区域点击：仅选中节点，不启动拖动（允许用户选中文本、滚动内容）

        case .nodeRotateHandle(let id):
            guard !isNodeLocked(id) else { return }
            guard let node = currentNodes.first(where: { $0.id == id }),
                  case .shape(let sc) = node.content else { return }
            let screenFrame = canvasRectToScreen(node.frame)
            let nodeCenter = CGPoint(x: screenFrame.midX, y: screenFrame.midY)
            let dx = loc.x - nodeCenter.x
            let dy = loc.y - nodeCenter.y
            let startAngle = atan2(dy, dx) - sc.rotation
            updateSelection(id, modifiers: event.modifierFlags)
            interaction = .rotatingNode(id, startAngle: startAngle, nodeCenter: nodeCenter)

        case .nodeResize(let id, let edge):
            guard !isNodeLocked(id) else { return }
            updateSelection(id, modifiers: event.modifierFlags)
            let canvasFrame = nodeCanvasFrames[id] ?? .zero
            let startFrame = canvasRectToScreen(canvasFrame)
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
            if event.modifierFlags.contains(.option) {
                interaction = .idle
                onDuplicateNode?(id)
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
            // 拖动开始时将焦点还给画布，防止 NSTextView 等内容视图在拖动中消费事件
            window?.makeFirstResponder(self)

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

            nodeCanvasFrames[id] = newFrame
            updateNodeFrameInPlace(id: id, frame: newFrame)
            needsLayout = true
            // 通知连线物理引擎：端点已移动
            onNodeFramesDuringDrag?([id])

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

            var updatedFrames: [UUID: CGRect] = [:]
            for (sid, sFrame) in startFrames {
                let newOrigin = CGPoint(x: sFrame.origin.x + finalDX, y: sFrame.origin.y + finalDY)
                let newFrame = CGRect(origin: newOrigin, size: sFrame.size)
                nodeCanvasFrames[sid] = newFrame
                updatedFrames[sid] = newFrame
            }
            updateNodeFramesInPlace(frames: updatedFrames)
            needsLayout = true
            // 通知连线物理引擎：多个端点已移动
            onNodeFramesDuringDrag?(Set(startFrames.keys))

        // --- Resize ---
        case .resizingNode(let id, let edge, let startFrame, let startMouse):
            guard nodeCanvasFrames[id] != nil else { return }
            let dx = loc.x - startMouse.x
            let dy = loc.y - startMouse.y
            applyResizeOnCanvas(id: id, edge: edge, dx: dx, dy: dy, startFrame: startFrame)

        // --- 旋转 ---
        case .rotatingNode(let id, let startAngle, let nodeCenter):
            let dx = loc.x - nodeCenter.x
            let dy = loc.y - nodeCenter.y
            let currentAngle = atan2(dy, dx)
            let newRotation = currentAngle - startAngle
            // Post notification for WorkspaceCanvasView to update ShapeContent.rotation
            NotificationCenter.default.post(
                name: .shapeNodeRotationChanged,
                object: nil,
                userInfo: ["nodeId": id, "rotation": newRotation]
            )

        // --- 框选 ---
        case .marquee(let start):
            marqueeCurrentPoint = loc
            let rect = CGRect(
                x: min(start.x, loc.x),
                y: min(start.y, loc.y),
                width: abs(loc.x - start.x),
                height: abs(loc.y - start.y)
            )
            snapGuideView?.selectionRect = rect
            needsDisplay = true

        // --- stroke 节点绘制模式（直线/箭头）---
        case .drawingStroke:
            drawingCurrentPoint = loc
            needsDisplay = true

        // --- freehand 节点绘制模式（自由笔，采样间距 4pt）---
        case .drawingFreehand(var pts):
            let last = pts.last ?? loc
            let dx = loc.x - last.x
            let dy = loc.y - last.y
            if dx * dx + dy * dy > 16 {
                pts.append(loc)
                interaction = .drawingFreehand(points: pts)
            }
            drawingCurrentPoint = loc
            needsDisplay = true

        // --- 节点绘制模式（网格吸附 + haptic）---
        case .drawing(let start):
            drawingCurrentPoint = loc

            // 将起点和当前点转为画布坐标，吸附到网格
            let grid = Constants.canvasGridSpacing
            let canvasStart = screenToCanvas(start)
            let canvasCurrent = screenToCanvas(loc)

            let snappedStartX = (canvasStart.x / grid).rounded() * grid
            let snappedStartY = (canvasStart.y / grid).rounded() * grid
            let snappedCurrentX = (canvasCurrent.x / grid).rounded() * grid
            let snappedCurrentY = (canvasCurrent.y / grid).rounded() * grid

            let snappedCanvasRect = CGRect(
                x: min(snappedStartX, snappedCurrentX),
                y: min(snappedStartY, snappedCurrentY),
                width: abs(snappedCurrentX - snappedStartX),
                height: abs(snappedCurrentY - snappedStartY)
            )

            // 检测网格跨越：矩形变化时触发触觉反馈
            if let lastRect = drawingLastSnappedRect, lastRect != snappedCanvasRect {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
            drawingLastSnappedRect = snappedCanvasRect

            // 将吸附后的画布矩形转回屏幕坐标用于绘制预览
            let screenOrigin = canvasToScreen(snappedCanvasRect.origin)
            let screenRect = CGRect(
                x: screenOrigin.x,
                y: screenOrigin.y,
                width: snappedCanvasRect.width * zoom,
                height: snappedCanvasRect.height * zoom
            )
            snapGuideView?.drawingRect = screenRect
            needsDisplay = true

        // --- 内容区交互（终端文字选中 / WebView 点击拖拽等）---
        case .contentInteraction(let id, let contentTarget):
            let correctedLocation: CGPoint
            if contentTarget is WKWebView {
                correctedLocation = correctedWindowLocationForWebView(for: event, nodeId: id, webView: contentTarget)
            } else {
                correctedLocation = correctedWindowLocation(for: event, nodeId: id, terminalView: contentTarget)
            }
            if let syntheticEvent = NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: correctedLocation,
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                eventNumber: event.eventNumber,
                clickCount: event.clickCount,
                pressure: event.pressure
            ) {
                contentTarget.mouseDragged(with: syntheticEvent)
            }

        // --- idle（连线工具跟踪）---
        case .idle:
            if connectingFromNodeId != nil {
                connectionDragPoint = loc
                needsDisplay = true
            }
        }
    }

    // MARK: - Resize 辅助

    private func applyResizeOnCanvas(id: UUID,
                                      edge: ResizeEdge,
                                      dx: CGFloat, dy: CGFloat,
                                      startFrame: CGRect) {
        let minW = CanvasNodeConstants.minNodeWidth * zoom
        let minH = CanvasNodeConstants.minNodeHeight * zoom
        let grid = Constants.canvasGridSpacing

        var x = startFrame.origin.x
        var y = startFrame.origin.y
        var w = startFrame.width
        var h = startFrame.height

        // startFrame 是屏幕坐标（缩放后），dx/dy 亦为屏幕坐标
        // isFlipped = true：y=0 在顶部，dy>0 向下
        switch edge {
        case .right:
            w = max(w + dx, minW)
        case .left:
            let newW = max(w - dx, minW)
            x = startFrame.maxX - newW
            w = newW
        case .bottom:
            h = max(h + dy, minH)
        case .top:
            let bottom = y + h
            let newH = max(h - dy, minH)
            y = bottom - newH
            h = newH
        case .bottomLeft:
            let newW = max(w - dx, minW)
            x = startFrame.maxX - newW
            w = newW
            h = max(h + dy, minH)
        case .bottomRight:
            w = max(w + dx, minW)
            h = max(h + dy, minH)
        case .topLeft:
            let newW = max(w - dx, minW)
            x = startFrame.maxX - newW
            w = newW
            let bottom = y + h
            let newH = max(h - dy, minH)
            y = bottom - newH
            h = newH
        case .topRight:
            w = max(w + dx, minW)
            let bottom = y + h
            let newH = max(h - dy, minH)
            y = bottom - newH
            h = newH
        }

        // 将活动边吸附到画布网格（与拖拽/绘制保持一致）
        // 先转为画布坐标取整，再转回屏幕坐标
        let rawCanvasOrigin = screenToCanvas(CGPoint(x: x, y: y))
        let rawCanvasW = w / zoom
        let rawCanvasH = h / zoom

        let snappedCanvasOrigin: CGPoint
        let snappedCanvasW: CGFloat
        let snappedCanvasH: CGFloat

        switch edge {
        case .right, .bottomRight, .topRight:
            // 右边活动：吸附右边
            let snappedRight = ((rawCanvasOrigin.x + rawCanvasW) / grid).rounded() * grid
            snappedCanvasW = max(snappedRight - rawCanvasOrigin.x, CanvasNodeConstants.minNodeWidth)
            snappedCanvasOrigin = rawCanvasOrigin
            snappedCanvasH = rawCanvasH
        case .left, .bottomLeft, .topLeft:
            // 左边活动：吸附左边（右边固定）
            let fixedRight = rawCanvasOrigin.x + rawCanvasW
            let snappedLeft = (rawCanvasOrigin.x / grid).rounded() * grid
            snappedCanvasW = max(fixedRight - snappedLeft, CanvasNodeConstants.minNodeWidth)
            snappedCanvasOrigin = CGPoint(x: fixedRight - snappedCanvasW, y: rawCanvasOrigin.y)
            snappedCanvasH = rawCanvasH
        case .bottom:
            // 下边活动：吸附下边
            let snappedBottom = ((rawCanvasOrigin.y + rawCanvasH) / grid).rounded() * grid
            snappedCanvasH = max(snappedBottom - rawCanvasOrigin.y, CanvasNodeConstants.minNodeHeight)
            snappedCanvasOrigin = rawCanvasOrigin
            snappedCanvasW = rawCanvasW
        case .top:
            // 上边活动：吸附上边（下边固定）
            let fixedBottom = rawCanvasOrigin.y + rawCanvasH
            let snappedTop = (rawCanvasOrigin.y / grid).rounded() * grid
            snappedCanvasH = max(fixedBottom - snappedTop, CanvasNodeConstants.minNodeHeight)
            snappedCanvasOrigin = CGPoint(x: rawCanvasOrigin.x, y: fixedBottom - snappedCanvasH)
            snappedCanvasW = rawCanvasW
        }

        let newCanvasFrame = CGRect(x: snappedCanvasOrigin.x, y: snappedCanvasOrigin.y,
                                    width: snappedCanvasW, height: snappedCanvasH)

        // 网格跨越时触发触觉反馈（与拖拽/绘制一致）
        if let prev = nodeCanvasFrames[id], prev != newCanvasFrame {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        nodeCanvasFrames[id] = newCanvasFrame
        // 同步更新 currentNodes，避免 layout() 重建 SwiftUI 视图时使用旧 frame 导致"弹回"
        updateNodeFrameInPlace(id: id, frame: newCanvasFrame)
        CATransaction.commit()
        needsLayout = true
        // 通知连线物理引擎：resize 也改变了节点中心
        onNodeFramesDuringDrag?([id])
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
            // 没有发生拖动 = 点击，发送节点激活通知
            NotificationCenter.default.post(
                name: .canvasNodeActivated,
                object: nil,
                userInfo: ["nodeId": id]
            )
            // text 节点：已选中时再次单击 → 进入编辑态
            if selectedNodeIds.contains(id),
               let node = currentNodes.first(where: { $0.id == id }),
               case .text = node.content {
                NotificationCenter.default.post(
                    name: .textNodeShouldBeginEditing,
                    object: nil,
                    userInfo: ["nodeId": id]
                )
            }
            // shape 节点编辑态触发已移至 mouseDown（NSTextView 始终注册，直接转发坐标修正事件）
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

        case .rotatingNode(let id, _, _):
            NotificationCenter.default.post(
                name: .shapeNodeRotationDidEnd,
                object: nil,
                userInfo: ["nodeId": id]
            )

        case .marquee(let start):
            if let current = marqueeCurrentPoint {
                let rect = CGRect(
                    x: min(start.x, current.x),
                    y: min(start.y, current.y),
                    width: abs(current.x - start.x),
                    height: abs(current.y - start.y)
                )
                if rect.width > 4 || rect.height > 4 {
                    let canvasRect = screenRectToCanvas(rect)
                    let hitIds = Set(nodeCanvasFrames.compactMap { (id, frame) in
                        frame.intersects(canvasRect) ? id : nil
                    })
                    selectedNodeIds = hitIds
                }
            }
            marqueeCurrentPoint = nil
            snapGuideView?.selectionRect = nil
            needsDisplay = true

        case .drawingStroke(let start):
            let canvasStart = screenToCanvas(start)
            guard let current = drawingCurrentPoint else {
                needsDisplay = true
                break
            }
            let canvasCurrent = screenToCanvas(current)
            let dx = canvasCurrent.x - canvasStart.x
            let dy = canvasCurrent.y - canvasStart.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist >= 10 {
                let minX = min(canvasStart.x, canvasCurrent.x)
                let minY = min(canvasStart.y, canvasCurrent.y)
                let maxX = max(canvasStart.x, canvasCurrent.x)
                let maxY = max(canvasStart.y, canvasCurrent.y)
                let padding: CGFloat = max(CGFloat(UserDefaults.standard.double(forKey: "drawingDefaultStrokeWidth")), 4)
                let boundingRect = CGRect(
                    x: minX - padding, y: minY - padding,
                    width: (maxX - minX) + padding * 2,
                    height: (maxY - minY) + padding * 2
                )
                NotificationCenter.default.post(
                    name: .strokeNodeDrawn,
                    object: nil,
                    userInfo: [
                        "nodeType": drawingNodeType,
                        "startPoint": canvasStart,
                        "endPoint": canvasCurrent,
                        "frame": boundingRect
                    ]
                )
            }
            drawingCurrentPoint = nil
            needsDisplay = true

        case .drawingFreehand(let pts):
            guard pts.count >= 2 else {
                drawingCurrentPoint = nil
                needsDisplay = true
                break
            }
            let canvasPts = pts.map { screenToCanvas($0) }
            let minX = canvasPts.map(\.x).min()!
            let minY = canvasPts.map(\.y).min()!
            let maxX = canvasPts.map(\.x).max()!
            let maxY = canvasPts.map(\.y).max()!
            let padding: CGFloat = 8
            let boundingRect = CGRect(
                x: minX - padding, y: minY - padding,
                width: (maxX - minX) + padding * 2,
                height: (maxY - minY) + padding * 2
            )
            let normalized = canvasPts.map { pt in
                CGPoint(
                    x: boundingRect.width > 0 ? (pt.x - boundingRect.minX) / boundingRect.width : 0.5,
                    y: boundingRect.height > 0 ? (pt.y - boundingRect.minY) / boundingRect.height : 0.5
                )
            }
            onFreehandDrawn?(drawingNodeType, normalized, boundingRect)
            drawingCurrentPoint = nil
            needsDisplay = true

        case .drawing(let start):
            // 使用网格吸附后的矩形创建节点
            let grid = Constants.canvasGridSpacing
            let canvasStart = screenToCanvas(start)
            let canvasCurrent = screenToCanvas(drawingCurrentPoint ?? start)

            let snappedStartX = (canvasStart.x / grid).rounded() * grid
            let snappedStartY = (canvasStart.y / grid).rounded() * grid
            let snappedCurrentX = (canvasCurrent.x / grid).rounded() * grid
            let snappedCurrentY = (canvasCurrent.y / grid).rounded() * grid

            let snappedRect = CGRect(
                x: min(snappedStartX, snappedCurrentX),
                y: min(snappedStartY, snappedCurrentY),
                width: abs(snappedCurrentX - snappedStartX),
                height: abs(snappedCurrentY - snappedStartY)
            )

            // text 节点只允许点击创建，不允许拖拽绘制
            let forceClickCreate = (drawingNodeType == "text")
            // 最小绘制尺寸判定（画布坐标 20pt）
            if !forceClickCreate && snappedRect.width > 20 && snappedRect.height > 20 {
                onNodeDrawn?(drawingNodeType, snappedRect)
            } else {
                // 点击创建：使用吸附后的起点作为中心
                let defaultSize = defaultNodeSize(for: drawingNodeType)
                let canvasRect = CGRect(
                    x: snappedStartX - defaultSize.width / 2,
                    y: snappedStartY - defaultSize.height / 2,
                    width: defaultSize.width,
                    height: defaultSize.height
                )
                onNodeDrawn?(drawingNodeType, canvasRect)
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            drawingCurrentPoint = nil
            drawingLastSnappedRect = nil
            snapGuideView?.drawingRect = nil
            needsDisplay = true

        case .contentInteraction(let id, let contentTarget):
            let correctedLocation: CGPoint
            if contentTarget is WKWebView {
                correctedLocation = correctedWindowLocationForWebView(for: event, nodeId: id, webView: contentTarget)
            } else {
                correctedLocation = correctedWindowLocation(for: event, nodeId: id, terminalView: contentTarget)
            }
            if let syntheticEvent = NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: correctedLocation,
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                eventNumber: event.eventNumber,
                clickCount: event.clickCount,
                pressure: event.pressure
            ) {
                contentTarget.mouseUp(with: syntheticEvent)
            }

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
        case .nodeRotateHandle:
            NSCursor.crosshair.set()
        case .nodeHeader, .nodeFooter, .nodeContent, .canvas:
            NSCursor.arrow.set()
        }
    }

    // MARK: - 终端鼠标坐标修正

    /// 修正转发给终端视图的鼠标事件坐标。
    ///
    /// 问题背景：节点通过 SwiftUI `.scaleEffect(zoom)` 缩放，这是 CALayer transform，
    /// 不影响 NSView 的 frame/bounds。因此 SwiftTerm 内部的
    /// `convert(event.locationInWindow, from: nil)` 基于 NSView 层级计算坐标时
    /// 不考虑 layer transform，导致映射到错误的终端行列位置。
    ///
    /// 修正方案：
    /// 1. 从画布屏幕坐标计算鼠标在终端内容区的相对位置（已缩放）
    /// 2. 除以 zoom 得到终端视图的本地坐标（未缩放）
    /// 3. 用 terminalView 自身的 convert(to: nil) 反向合成正确的窗口坐标
    ///    使 SwiftTerm 的 convert(from: nil) 能正确还原到本地坐标
    private func correctedWindowLocation(for event: NSEvent, nodeId: UUID, terminalView: NSView) -> CGPoint {
        let loc = convert(event.locationInWindow, from: nil)

        guard let node = currentNodes.first(where: { $0.id == nodeId }) else {
            return event.locationInWindow
        }

        let screenFrame = canvasRectToScreen(node.frame)
        let scaledHeaderHeight = CanvasNodeConstants.headerHeight * zoom

        // 终端节点有 footer，需要减去；加上 divider（约 1pt 缩放后）
        let scaledDividerHeight: CGFloat = 1.0 * zoom

        // 鼠标在节点内容区中的相对位置（屏幕坐标，已乘以 zoom）
        let relX = loc.x - screenFrame.minX
        let relY = loc.y - screenFrame.minY - scaledHeaderHeight - scaledDividerHeight

        // 转为终端视图本地坐标（未缩放）
        // SwiftTerm TerminalView 是非 flipped 的（y 从底部向上），需要翻转 y 轴
        let tvHeight = terminalView.bounds.height
        let localX = relX / zoom
        let localY = tvHeight - (relY / zoom)

        // 用 terminalView 自身的坐标系统转回窗口坐标
        // 这样 SwiftTerm 调用 convert(locationInWindow, from: nil) 时得到 (localX, localY)
        return terminalView.convert(CGPoint(x: localX, y: localY), to: nil)
    }

    /// Portal WKWebView 坐标修正
    /// WKWebView 是 flipped 坐标系（y 从上到下），且 Portal 节点有 header + navBar + divider 偏移
    private func correctedWindowLocationForWebView(for event: NSEvent, nodeId: UUID, webView: NSView) -> CGPoint {
        let loc = convert(event.locationInWindow, from: nil)

        guard let node = currentNodes.first(where: { $0.id == nodeId }) else {
            return event.locationInWindow
        }

        let screenFrame = canvasRectToScreen(node.frame)
        // Portal 内容区偏移：header(32) + navBar padding(6) + navBar height(28) + padding(6) + divider(1) = 73
        let contentTopOffset: CGFloat = 73.0
        let scaledContentTop = contentTopOffset * zoom

        // 鼠标在 WebView 内容区中的相对位置（屏幕坐标）
        let relX = loc.x - screenFrame.minX
        let relY = loc.y - screenFrame.minY - scaledContentTop

        // 转为 WebView 本地坐标（未缩放）
        // WKWebView 是 flipped（y 从上到下），与屏幕坐标系一致（AppKit 的 y 向下）
        let localX = relX / zoom
        let localY = relY / zoom

        // 用 webView 自身坐标系统转回窗口坐标
        return webView.convert(CGPoint(x: localX, y: localY), to: nil)
    }


    /// NSTextView 坐标修正（Shape 节点）
    /// Shape 节点无 header/footer，NSTextView 覆盖整个节点 frame，只需减去 frame 原点
    private func correctedWindowLocationForShapeTextView(for event: NSEvent, nodeId: UUID, textView: NSView) -> CGPoint {
        let loc = convert(event.locationInWindow, from: nil)

        guard let node = currentNodes.first(where: { $0.id == nodeId }) else {
            return event.locationInWindow
        }

        let screenFrame = canvasRectToScreen(node.frame)

        let relX = loc.x - screenFrame.minX
        let relY = loc.y - screenFrame.minY

        let localX = relX / zoom
        let localY = relY / zoom

        return textView.convert(CGPoint(x: localX, y: localY), to: nil)
    }

    /// NSTextView 坐标修正（Note 节点）
    /// NSTextView 默认 isFlipped=true（y 从上到下），与屏幕坐标系一致，不需要翻转 y 轴
    private func correctedWindowLocationForTextView(for event: NSEvent, nodeId: UUID, textView: NSView) -> CGPoint {
        let loc = convert(event.locationInWindow, from: nil)

        guard let node = currentNodes.first(where: { $0.id == nodeId }) else {
            return event.locationInWindow
        }

        let screenFrame = canvasRectToScreen(node.frame)
        let scaledHeaderHeight = CanvasNodeConstants.headerHeight * zoom
        let scaledDividerHeight: CGFloat = 1.0 * zoom

        // 鼠标在 NSTextView 内容区中的相对位置（屏幕坐标）
        let relX = loc.x - screenFrame.minX
        let relY = loc.y - screenFrame.minY - scaledHeaderHeight - scaledDividerHeight

        // NSTextView 是 flipped（y 从上到下），与屏幕坐标方向一致，直接除以 zoom
        let localX = relX / zoom
        let localY = relY / zoom

        return textView.convert(CGPoint(x: localX, y: localY), to: nil)
    }
}
