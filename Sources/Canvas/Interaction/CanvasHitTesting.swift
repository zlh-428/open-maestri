import AppKit

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

            // stroke/freehand 节点：路径距离命中（不用矩形，只有靠近实际线段才算命中）
            if case .stroke(let sc) = node.content {
                let hitRadius: CGFloat = max(6, sc.strokeWidth * zoom * 0.5 + 4)
                guard screenFrame.insetBy(dx: -hitRadius, dy: -hitRadius).contains(loc) else { continue }
                let localPt = CGPoint(x: loc.x - screenFrame.minX, y: loc.y - screenFrame.minY)
                let w = screenFrame.width
                let h = screenFrame.height
                let start   = CGPoint(x: sc.startPoint.x * w, y: sc.startPoint.y * h)
                let end     = CGPoint(x: sc.endPoint.x   * w, y: sc.endPoint.y   * h)
                let onPath: Bool
                if sc.strokeType == .arrow, let cp = sc.controlPoint {
                    let ctrl = CGPoint(x: cp.x * w, y: cp.y * h)
                    onPath = distanceToQuadBezier(localPt, p0: start, p1: ctrl, p2: end) <= hitRadius
                } else {
                    onPath = distanceToSegment(localPt, a: start, b: end) <= hitRadius
                }
                guard onPath else { continue }
                let r = CanvasHitTestResult.nodeContent(node.id, nodesHostingView ?? self)
                _hitTestCachedPoint = loc; _hitTestCachedResult = r
                return r
            }

            if case .freehand(let fc) = node.content {
                let hitRadius: CGFloat = max(6, fc.strokeWidth * zoom * 0.5 + 4)
                guard screenFrame.insetBy(dx: -hitRadius, dy: -hitRadius).contains(loc) else { continue }
                let localPt = CGPoint(x: loc.x - screenFrame.minX, y: loc.y - screenFrame.minY)
                let w = screenFrame.width
                let h = screenFrame.height
                let pts = fc.points.map { CGPoint(x: $0.x * w, y: $0.y * h) }
                var hit = false
                for i in 0..<pts.count - 1 {
                    if distanceToSegment(localPt, a: pts[i], b: pts[i + 1]) <= hitRadius { hit = true; break }
                }
                guard hit else { continue }
                let r = CanvasHitTestResult.nodeContent(node.id, nodesHostingView ?? self)
                _hitTestCachedPoint = loc; _hitTestCachedResult = r
                return r
            }

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

    func isNodeLocked(_ id: UUID) -> Bool {
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

    // MARK: - 几何辅助：路径距离命中检测

    /// 点到线段的最短距离
    private func distanceToSegment(_ p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// 点到二次贝塞尔曲线的近似最短距离（20 段线性采样）
    private func distanceToQuadBezier(_ p: CGPoint, p0: CGPoint, p1: CGPoint, p2: CGPoint) -> CGFloat {
        let steps = 20
        var minDist = CGFloat.greatestFiniteMagnitude
        var prev = p0
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let mt = 1 - t
            let cur = CGPoint(x: mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x,
                              y: mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y)
            let d = distanceToSegment(p, a: prev, b: cur)
            if d < minDist { minDist = d }
            prev = cur
        }
        return minDist
    }
}
