import AppKit

/// 所有连线的渲染层 NSView（Story 5.1 AC）
/// - 覆盖在画布上方，通过 draw(_:) 用 RopePathRenderer 绘制所有活跃连接
/// - 连线以物理绳索动画渲染（悬链线，21 个控制点，Story 5.1 AC）
/// - 颜色状态编码：灰色（空闲）→ 绿色 glow（通信中）→ 红色（断开）（UX-DR5）
final class ConnectionOverlayView: NSView {

    // MARK: - 数据源

    /// 当前需要绘制的连接列表（由画布在节点移动/连接变化时更新）
    var connections: [RenderableConnection] = [] {
        didSet { needsDisplay = true }
    }

    // MARK: - 初始化

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    // MARK: - 绘制（Story 5.1 AC：连线实时重新计算悬链线，60fps）

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for conn in connections {
            RopePathRenderer.draw(points: conn.screenPoints, status: conn.status)

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
