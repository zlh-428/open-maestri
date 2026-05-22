import AppKit

/// 所有连线的渲染层 NSView（Story 5.1 AC）
/// - 覆盖在画布上方，通过 draw(_:) 用 RopePathRenderer 绘制所有活跃连接
/// - 连线以物理绳索动画渲染（悬链线，21 个控制点，Story 5.1 AC）
/// - 颜色状态编码：灰色（空闲）→ 绿色 glow（通信中）→ 红色（断开）（UX-DR5）
/// - 支持 hover 高亮和右键删除连线
final class ConnectionOverlayView: NSView {
    override var isFlipped: Bool { true }

    // MARK: - 数据源

    /// 当前需要绘制的连接列表（由画布在节点移动/连接变化时更新）
    /// 仅当连线数据实际变化时才触发重绘（避免 viewport pan/zoom 时的冗余重绘）
    var connections: [RenderableConnection] = [] {
        didSet {
            guard connectionsDidChange(old: oldValue, new: connections) else { return }
            needsDisplay = true
        }
    }

    /// 快速判断连线数据是否有实际变化
    /// 比较策略：数量 → 各连线 id + 首尾中点（覆盖 95% 场景，避免逐点全量比较）
    private func connectionsDidChange(old: [RenderableConnection], new: [RenderableConnection]) -> Bool {
        guard old.count == new.count else { return true }
        for i in old.indices {
            let o = old[i], n = new[i]
            if o.id != n.id || o.status != n.status { return true }
            // 比较首点、尾点、中点三个采样位置
            guard o.screenPoints.count == n.screenPoints.count,
                  !o.screenPoints.isEmpty else { return o.screenPoints.count != n.screenPoints.count }
            let midIdx = o.screenPoints.count / 2
            if !pointsEqual(o.screenPoints[0], n.screenPoints[0]) ||
               !pointsEqual(o.screenPoints[midIdx], n.screenPoints[midIdx]) ||
               !pointsEqual(o.screenPoints[o.screenPoints.count - 1], n.screenPoints[n.screenPoints.count - 1]) {
                return true
            }
        }
        return false
    }

    /// 浮点坐标比较（容差 0.5 像素，避免亚像素抖动触发重绘）
    private func pointsEqual(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 0.5 && abs(a.y - b.y) < 0.5
    }

    /// 当前 hover 高亮的连线 ID
    private var highlightedConnectionId: UUID? {
        didSet {
            if oldValue != highlightedConnectionId { needsDisplay = true }
        }
    }

    /// 连线删除回调（传入连线 UUID）
    var onDeleteConnection: ((UUID) -> Void)?

    /// 连线命中检测容差（像素）
    private static let hitTolerance: CGFloat = 8.0

    // MARK: - 临时连线数据（连线工具拖动期间由 CanvasViewportView 同步）

    /// 临时连线起点节点的屏幕坐标 frame
    var tempConnectionFromFrame: CGRect? = nil {
        didSet { if oldValue != tempConnectionFromFrame { needsDisplay = true } }
    }
    /// 临时连线终点（鼠标当前屏幕坐标）
    var tempConnectionToPoint: CGPoint? = nil {
        didSet { if oldValue != tempConnectionToPoint { needsDisplay = true } }
    }

    // MARK: - 初始化

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        setupTracking()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = .clear
        setupTracking()
    }

    private func setupTracking() {
        // 初始 tracking area，会在 updateTrackingAreas 中刷新
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    // MARK: - 鼠标事件

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        highlightedConnectionId = connectionId(at: loc)
        if highlightedConnectionId != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        highlightedConnectionId = nil
        NSCursor.arrow.set()
    }

    /// 右键点击连线弹出删除菜单
    override func rightMouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard let connId = connectionId(at: loc) else {
            super.rightMouseDown(with: event)
            return
        }
        highlightedConnectionId = connId

        let menu = NSMenu()
        let deleteTitle = "connection.delete".localized
        let deleteItem = NSMenuItem(title: deleteTitle, action: #selector(deleteHighlightedConnection), keyEquivalent: "")
        let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]
        deleteItem.attributedTitle = NSAttributedString(string: deleteTitle, attributes: attrs)
        deleteItem.target = self
        menu.addItem(deleteItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func deleteHighlightedConnection() {
        guard let connId = highlightedConnectionId else { return }
        onDeleteConnection?(connId)
        highlightedConnectionId = nil
    }

    /// 让鼠标事件穿透到下层（仅在连线上方时拦截）
    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        if connectionId(at: localPoint) != nil {
            return self
        }
        return nil  // 穿透到下层
    }

    // MARK: - 连线命中检测

    /// 查找距离指定点最近的连线（在容差范围内）
    /// - Parameter point: 本视图坐标系中的点
    /// - Returns: 命中的连线 UUID，nil 表示未命中
    func connectionId(at point: CGPoint) -> UUID? {
        var bestId: UUID?
        var bestDist: CGFloat = Self.hitTolerance

        for conn in connections {
            let dist = minDistance(from: point, to: conn.screenPoints)
            if dist < bestDist {
                bestDist = dist
                bestId = conn.id
            }
        }
        return bestId
    }

    /// 计算点到折线段的最小距离
    private func minDistance(from point: CGPoint, to polyline: [CGPoint]) -> CGFloat {
        guard polyline.count >= 2 else { return .greatestFiniteMagnitude }
        var minDist: CGFloat = .greatestFiniteMagnitude
        for i in 0..<(polyline.count - 1) {
            let d = distanceToSegment(point: point, a: polyline[i], b: polyline[i + 1])
            if d < minDist { minDist = d }
        }
        return minDist
    }

    /// 点到线段的距离
    private func distanceToSegment(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else {
            return hypot(point.x - a.x, point.y - a.y)
        }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        return hypot(point.x - projX, point.y - projY)
    }

    // MARK: - 绘制（Story 5.1 AC：连线实时重新计算悬链线，60fps）

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // dirtyRect 裁剪：仅绘制 bounding box 与 dirtyRect 相交的连线
        let inflatedDirty = dirtyRect.insetBy(dx: -10, dy: -10) // 扩展少许容差避免边缘截断
        for conn in connections {
            // 快速 bounding box 检测：用首尾中三点估算连线包围盒
            guard !conn.screenPoints.isEmpty else { continue }
            let bbox = boundingBox(of: conn.screenPoints)
            guard inflatedDirty.intersects(bbox) else { continue }

            let isHighlighted = conn.id == highlightedConnectionId
            RopePathRenderer.draw(points: conn.screenPoints, status: conn.status, isHighlighted: isHighlighted)

            // 状态文字（正在注入 Skill... / Skill 已注入双端）
            if let label = conn.statusLabel, let mid = RopePathRenderer.midpoint(of: conn.screenPoints) {
                drawLabel(label, at: mid)
            }
        }

        // 临时连线绘制（连线工具拖动时）
        drawTemporaryConnectionLine()
    }

    // MARK: - 临时连线绘制

    /// 绘制连线工具拖动时的临时虚线（直线）
    private func drawTemporaryConnectionLine() {
        guard let fromFrame = tempConnectionFromFrame else { return }

        // 鼠标未移动时，绘制四个边缘连接点指示器
        guard let toPoint = tempConnectionToPoint else {
            drawEdgeConnectors(on: fromFrame)
            return
        }

        // 计算从节点边缘出发的锚点（向鼠标方向与边框的交点）
        let fromCenter = CGPoint(x: fromFrame.midX, y: fromFrame.midY)
        let fromPoint = Self.edgeAnchor(of: fromFrame, center: fromCenter, toward: toPoint)

        // 绘制虚线直线
        let path = NSBezierPath()
        path.move(to: fromPoint)
        path.line(to: toPoint)
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
        path.stroke()

        // 起点连接点指示器（在节点边缘出发点画小圆圈）
        drawConnectorDot(at: fromPoint)

        // 终点指示器（鼠标位置画小圆圈）
        drawConnectorDot(at: toPoint, color: NSColor.systemBlue.withAlphaComponent(0.5))

        // 源节点边框高亮（淡蓝色）
        let borderPath = NSBezierPath(roundedRect: fromFrame, xRadius: 6, yRadius: 6)
        borderPath.lineWidth = 1.5
        NSColor.systemBlue.withAlphaComponent(0.4).setStroke()
        borderPath.stroke()
    }

    /// 在节点四个边缘中点绘制连接点圆圈（连线模式激活但鼠标未移动时）
    private func drawEdgeConnectors(on frame: CGRect) {
        let midPoints = [
            CGPoint(x: frame.midX, y: frame.minY),  // 上
            CGPoint(x: frame.midX, y: frame.maxY),  // 下
            CGPoint(x: frame.minX, y: frame.midY),  // 左
            CGPoint(x: frame.maxX, y: frame.midY),  // 右
        ]

        // 节点边框高亮
        let borderPath = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
        borderPath.lineWidth = 1.5
        NSColor.systemBlue.withAlphaComponent(0.4).setStroke()
        borderPath.stroke()

        // 四个连接点
        for pt in midPoints {
            drawConnectorDot(at: pt)
        }
    }

    /// 绘制连接器圆点（蓝色外圈 + 白色内圈）
    private func drawConnectorDot(at point: CGPoint, color: NSColor = .systemBlue) {
        let outerRadius: CGFloat = 5.0
        let innerRadius: CGFloat = 2.5
        let outerRect = CGRect(
            x: point.x - outerRadius, y: point.y - outerRadius,
            width: outerRadius * 2, height: outerRadius * 2
        )
        color.setFill()
        NSBezierPath(ovalIn: outerRect).fill()

        let innerRect = CGRect(
            x: point.x - innerRadius, y: point.y - innerRadius,
            width: innerRadius * 2, height: innerRadius * 2
        )
        NSColor.white.setFill()
        NSBezierPath(ovalIn: innerRect).fill()
    }

    // MARK: - 边缘锚点计算

    /// 计算从节点边框出发的锚点（从 frame 中心向 target 方向做射线，返回与边框的交点）
    static func edgeAnchor(of frame: CGRect, center: CGPoint, toward target: CGPoint) -> CGPoint {
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

    /// 计算控制点序列的 axis-aligned bounding box
    private func boundingBox(of points: [CGPoint]) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for p in points {
            if p.x < minX { minX = p.x }
            if p.y < minY { minY = p.y }
            if p.x > maxX { maxX = p.x }
            if p.y > maxY { maxY = p.y }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func drawLabel(_ text: String, at point: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.6),
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        attributed.draw(at: CGPoint(x: point.x - 40, y: point.y + 4))
    }

    // MARK: - 更新连线位置（节点拖动时实时调用）

    func updateConnection(id: UUID, screenPoints: [CGPoint]) {
        if let idx = connections.firstIndex(where: { $0.id == id }) {
            connections[idx].screenPoints = screenPoints
        }
    }

    func addConnection(_ conn: RenderableConnection) {
        if !connections.contains(where: { $0.id == conn.id }) {
            connections.append(conn)
        }
    }

    func removeConnection(id: UUID) {
        connections.removeAll { $0.id == id }
    }

    func updateStatus(_ status: ConnectionStatus, for id: UUID) {
        if let idx = connections.firstIndex(where: { $0.id == id }) {
            connections[idx].status = status
            needsDisplay = true
        }
    }
}

/// 可渲染连接数据（画布坐标已转换为屏幕坐标）
struct RenderableConnection {
    let id: UUID
    var screenPoints: [CGPoint]  // 21 个控制点（已转换为屏幕坐标）
    var status: ConnectionStatus
    var statusLabel: String?     // nil 表示不显示标签
}
