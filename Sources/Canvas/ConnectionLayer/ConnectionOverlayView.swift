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
        let deleteTitle = String(localized: "connection.delete")
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
    private func connectionId(at point: CGPoint) -> UUID? {
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
        for conn in connections {
            let isHighlighted = conn.id == highlightedConnectionId
            RopePathRenderer.draw(points: conn.screenPoints, status: conn.status, isHighlighted: isHighlighted)

            // 状态文字（正在注入 Skill... / Skill 已注入双端）
            if let label = conn.statusLabel, let mid = RopePathRenderer.midpoint(of: conn.screenPoints) {
                drawLabel(label, at: mid)
            }
        }
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
