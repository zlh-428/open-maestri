import AppKit
import CoreGraphics

/// 绳索路径渲染器
/// 根据 21 个悬链线控制点生成平滑 NSBezierPath，支持连接状态颜色编码（UX-DR5）
struct RopePathRenderer {

    // MARK: - 颜色状态编码（UX-DR5）
    // 灰色（空闲）→ 绿色 glow（通信中）→ 橙色（断开）→ 红色（错误）

    static func strokeColor(for status: ConnectionStatus) -> NSColor {
        switch status {
        case .idle:          return NSColor.systemGray.withAlphaComponent(0.7)
        case .communicating: return NSColor.systemGreen
        case .disconnected:  return NSColor.systemRed
        case .error:         return NSColor.systemOrange
        }
    }

    static func lineWidth(for status: ConnectionStatus) -> CGFloat {
        status == .communicating ? 2.5 : 1.5
    }

    static func isDashed(for status: ConnectionStatus) -> Bool {
        status == .idle || status == .disconnected
    }

    // MARK: - 路径生成

    /// 从 21 个控制点生成平滑 Catmull-Rom 样条曲线
    static func bezierPath(from points: [CGPoint]) -> NSBezierPath {
        guard points.count >= 2 else { return NSBezierPath() }
        let path = NSBezierPath()
        path.move(to: points[0])

        for i in 1..<points.count {
            let prev = points[max(0, i - 2)]
            let p0   = points[i - 1]
            let p1   = points[i]
            let next = points[min(points.count - 1, i + 1)]

            let cp1 = CGPoint(
                x: p0.x + (p1.x - prev.x) / 6.0,
                y: p0.y + (p1.y - prev.y) / 6.0
            )
            let cp2 = CGPoint(
                x: p1.x - (next.x - p0.x) / 6.0,
                y: p1.y - (next.y - p0.y) / 6.0
            )
            path.curve(to: p1, controlPoint1: cp1, controlPoint2: cp2)
        }
        return path
    }

    /// 从序列化的 [[Double]] 点数组生成路径
    static func bezierPath(from rawPoints: [[Double]]) -> NSBezierPath {
        let pts = rawPoints.compactMap { arr -> CGPoint? in
            guard arr.count >= 2 else { return nil }
            return CGPoint(x: arr[0], y: arr[1])
        }
        return bezierPath(from: pts)
    }

    // MARK: - 绘制

    /// 绘制连接线（状态颜色 + 虚线）
    static func draw(points: [CGPoint], status: ConnectionStatus) {
        guard !points.isEmpty else { return }
        let path = bezierPath(from: points)
        strokeColor(for: status).setStroke()
        path.lineWidth = lineWidth(for: status)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        if isDashed(for: status) {
            let pattern: [CGFloat] = [6, 4]
            path.setLineDash(pattern, count: 2, phase: 0)
        }
        path.stroke()
    }

    // MARK: - 中点（用于显示状态文字）

    static func midpoint(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        return points[points.count / 2]
    }
}
