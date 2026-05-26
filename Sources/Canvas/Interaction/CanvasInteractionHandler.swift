import AppKit
import WebKit

// MARK: - CanvasViewportView 鼠标事件处理

extension CanvasViewportView {

    // MARK: - 统一鼠标事件处理

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        // 0. stroke 控制点优先命中检测（必须在选中状态下，且最高优先级）
        for node in currentNodes.reversed() {
            guard selectedNodeIds.contains(node.id),
                  case .stroke(let sc) = node.content,
                  let frame = nodeCanvasFrames[node.id] else { continue }
            let screenFrame = canvasRectToScreen(frame)
            var candidates: [(role: String, pt: CGPoint)] = [
                ("start", CGPoint(x: screenFrame.minX + sc.startPoint.x * screenFrame.width,
                                   y: screenFrame.minY + sc.startPoint.y * screenFrame.height)),
                ("end",   CGPoint(x: screenFrame.minX + sc.endPoint.x * screenFrame.width,
                                   y: screenFrame.minY + sc.endPoint.y * screenFrame.height)),
            ]
            if let cp = sc.controlPoint {
                candidates.append(("control",
                    CGPoint(x: screenFrame.minX + cp.x * screenFrame.width,
                             y: screenFrame.minY + cp.y * screenFrame.height)))
            }
            for (role, pt) in candidates {
                if hypot(loc.x - pt.x, loc.y - pt.y) < 8 {
                    interaction = .draggingStrokePoint(node.id, pointRole: role, startContent: sc, startFrame: frame)
                    return
                }
            }
        }

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
            // stroke/freehand 节点：内容区也支持拖动（无文字选择需求）
            if let node = currentNodes.first(where: { $0.id == id }) {
                switch node.content {
                case .stroke, .freehand:
                    let startFrame = nodeCanvasFrames[id] ?? .zero
                    interaction = .mayDragNode(id, startMouse: loc, startFrame: startFrame, contentTarget: nil)
                default:
                    break
                }
            }

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
        case .drawingStroke(let start):
            drawingCurrentPoint = loc
            snapGuideView?.strokePreviewPath = (start: start, end: loc, type: drawingNodeType)
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
            // 传递当前累积点（若未追加当前点则附加，保证预览实时跟手）
            let previewPts = pts.last == loc ? pts : pts + [loc]
            snapGuideView?.freehandPreviewPoints = previewPts
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

        // --- stroke 控制点拖拽 ---
        case .draggingStrokePoint(let id, let role, let origContent, let startFrame):
            let canvasLoc = screenToCanvas(loc)

            if role == "control" {
                // 拖动贝塞尔控制点：frame 跟随扩展，start/end 画布绝对坐标保持不变
                let absStart = CGPoint(
                    x: startFrame.minX + origContent.startPoint.x * startFrame.width,
                    y: startFrame.minY + origContent.startPoint.y * startFrame.height
                )
                let absEnd = CGPoint(
                    x: startFrame.minX + origContent.endPoint.x * startFrame.width,
                    y: startFrame.minY + origContent.endPoint.y * startFrame.height
                )
                let absControl = canvasLoc
                let padding: CGFloat = 20
                let newMinX = min(absStart.x, absEnd.x, absControl.x) - padding
                let newMinY = min(absStart.y, absEnd.y, absControl.y) - padding
                let newMaxX = max(absStart.x, absEnd.x, absControl.x) + padding
                let newMaxY = max(absStart.y, absEnd.y, absControl.y) + padding
                let newFrame = CGRect(x: newMinX, y: newMinY,
                                     width: newMaxX - newMinX,
                                     height: newMaxY - newMinY)
                let nw = newFrame.width
                let nh = newFrame.height
                var updated = origContent
                updated.startPoint   = CGPoint(x: nw > 0 ? (absStart.x   - newMinX) / nw : 0.5,
                                               y: nh > 0 ? (absStart.y   - newMinY) / nh : 0.5)
                updated.endPoint     = CGPoint(x: nw > 0 ? (absEnd.x     - newMinX) / nw : 0.5,
                                               y: nh > 0 ? (absEnd.y     - newMinY) / nh : 0.5)
                updated.controlPoint = CGPoint(x: nw > 0 ? (absControl.x - newMinX) / nw : 0.5,
                                               y: nh > 0 ? (absControl.y - newMinY) / nh : 0.5)
                nodeCanvasFrames[id] = newFrame
                let newContent = NodeContent.stroke(updated)
                NotificationCenter.default.post(
                    name: .canvasNodeContentChanged,
                    object: nil,
                    userInfo: ["nodeId": id, "content": newContent, "frame": newFrame]
                )
            } else {
                // 拖动 start/end：仅归一化坐标更新，frame 不变
                let w = startFrame.width
                let h = startFrame.height
                let normalized = CGPoint(
                    x: w > 0 ? (canvasLoc.x - startFrame.minX) / w : 0.5,
                    y: h > 0 ? (canvasLoc.y - startFrame.minY) / h : 0.5
                )
                var updated = origContent
                switch role {
                case "start": updated.startPoint = normalized
                case "end":   updated.endPoint   = normalized
                default: break
                }
                let newContent = NodeContent.stroke(updated)
                NotificationCenter.default.post(
                    name: .canvasNodeContentChanged,
                    object: nil,
                    userInfo: ["nodeId": id, "content": newContent]
                )
            }

        // --- idle（连线工具跟踪）---
        case .idle:
            if connectingFromNodeId != nil {
                connectionDragPoint = loc
                needsDisplay = true
            }
        }
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
                snapGuideView?.strokePreviewPath = nil
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
            snapGuideView?.strokePreviewPath = nil
            needsDisplay = true

        case .drawingFreehand(let pts):
            guard pts.count >= 2 else {
                drawingCurrentPoint = nil
                snapGuideView?.freehandPreviewPoints = nil
                needsDisplay = true
                break
            }
            let canvasPts = pts.map { screenToCanvas($0) }
            guard let minX = canvasPts.map(\.x).min(),
                  let minY = canvasPts.map(\.y).min(),
                  let maxX = canvasPts.map(\.x).max(),
                  let maxY = canvasPts.map(\.y).max() else {
                drawingCurrentPoint = nil
                snapGuideView?.freehandPreviewPoints = nil
                interaction = .idle
                needsDisplay = true
                break
            }
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
            snapGuideView?.freehandPreviewPoints = nil
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

            if drawingNodeType == "text" {
                // text 节点：点击即创建，使用默认尺寸居中于点击点
                let defaultSize = defaultNodeSize(for: drawingNodeType)
                let canvasRect = CGRect(
                    x: snappedStartX - defaultSize.width / 2,
                    y: snappedStartY - defaultSize.height / 2,
                    width: defaultSize.width,
                    height: defaultSize.height
                )
                onNodeDrawn?(drawingNodeType, canvasRect)
            } else if snappedRect.width > 20 && snappedRect.height > 20 {
                // 其余节点：必须拖拽超过 20pt 才创建
                onNodeDrawn?(drawingNodeType, snappedRect)
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

        case .draggingStrokePoint(let id, let role, let origContent, let startFrame):
            let loc2 = convert(event.locationInWindow, from: nil)
            let canvasLoc2 = screenToCanvas(loc2)

            var finalContent = origContent
            var finalFrame: CGRect? = nil

            if role == "control" {
                let absStart = CGPoint(
                    x: startFrame.minX + origContent.startPoint.x * startFrame.width,
                    y: startFrame.minY + origContent.startPoint.y * startFrame.height
                )
                let absEnd = CGPoint(
                    x: startFrame.minX + origContent.endPoint.x * startFrame.width,
                    y: startFrame.minY + origContent.endPoint.y * startFrame.height
                )
                let absControl = canvasLoc2
                let padding: CGFloat = 20
                let newMinX = min(absStart.x, absEnd.x, absControl.x) - padding
                let newMinY = min(absStart.y, absEnd.y, absControl.y) - padding
                let newMaxX = max(absStart.x, absEnd.x, absControl.x) + padding
                let newMaxY = max(absStart.y, absEnd.y, absControl.y) + padding
                let newFrame = CGRect(x: newMinX, y: newMinY,
                                     width: newMaxX - newMinX,
                                     height: newMaxY - newMinY)
                let nw = newFrame.width
                let nh = newFrame.height
                finalContent.startPoint   = CGPoint(x: nw > 0 ? (absStart.x   - newMinX) / nw : 0.5,
                                                    y: nh > 0 ? (absStart.y   - newMinY) / nh : 0.5)
                finalContent.endPoint     = CGPoint(x: nw > 0 ? (absEnd.x     - newMinX) / nw : 0.5,
                                                    y: nh > 0 ? (absEnd.y     - newMinY) / nh : 0.5)
                finalContent.controlPoint = CGPoint(x: nw > 0 ? (absControl.x - newMinX) / nw : 0.5,
                                                    y: nh > 0 ? (absControl.y - newMinY) / nh : 0.5)
                finalFrame = newFrame
            } else {
                let w = startFrame.width
                let h = startFrame.height
                let normalized = CGPoint(
                    x: w > 0 ? (canvasLoc2.x - startFrame.minX) / w : 0.5,
                    y: h > 0 ? (canvasLoc2.y - startFrame.minY) / h : 0.5
                )
                switch role {
                case "start": finalContent.startPoint = normalized
                case "end":   finalContent.endPoint   = normalized
                default: break
                }
            }

            var userInfo: [String: Any] = ["nodeId": id, "content": NodeContent.stroke(finalContent)]
            if let f = finalFrame { userInfo["frame"] = f }
            NotificationCenter.default.post(
                name: .strokePointDragDidEnd,
                object: nil,
                userInfo: userInfo
            )

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

}
