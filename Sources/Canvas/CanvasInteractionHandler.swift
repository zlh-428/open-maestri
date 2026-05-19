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
}
