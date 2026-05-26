import SwiftUI
import AppKit

struct StrokeNodeSwiftUIView: View {
    let nodeId: UUID
    let content: StrokeContent
    let isSelected: Bool
    let zoom: CGFloat
    var onContentChange: ((StrokeContent) -> Void)?
    var onClose: ((UUID) -> Void)?

    // 贝塞尔控制点可超出 frame，预留 overflow 绘制区域（画布坐标单位）
    private static let curveOverflow: CGFloat = 300

    var body: some View {
        ZStack {
            strokeCanvas
            if isSelected {
                controlPointsLayer
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - 渲染主体

    private var strokeCanvas: some View {
        GeometryReader { geo in
            let overflow = Self.curveOverflow
            Canvas { context, _ in
                // 使用 geo.size 作为逻辑尺寸（与 frame 对应）
                let size = geo.size
                let start = CGPoint(x: content.startPoint.x * size.width,
                                    y: content.startPoint.y * size.height)
                let end   = CGPoint(x: content.endPoint.x * size.width,
                                    y: content.endPoint.y * size.height)

                let strokeColor = resolveColor(content.strokeColor)
                let strokeStyle: StrokeStyle
                switch content.strokeStyle {
                case .solid:  strokeStyle = StrokeStyle(lineWidth: content.strokeWidth, lineCap: .round)
                case .dashed: strokeStyle = StrokeStyle(lineWidth: content.strokeWidth, lineCap: .round, dash: [8, 4])
                case .dotted: strokeStyle = StrokeStyle(lineWidth: content.strokeWidth, lineCap: .round, dash: [2, 4])
                }

                // 将坐标系向右下偏移 overflow，使 (0,0) 对应逻辑原点
                context.translateBy(x: overflow, y: overflow)

                var path = Path()
                if content.strokeType == .arrow, let cp = content.controlPoint {
                    let ctrl = CGPoint(x: cp.x * size.width, y: cp.y * size.height)
                    path.move(to: start)
                    path.addQuadCurve(to: end, control: ctrl)
                } else {
                    path.move(to: start)
                    path.addLine(to: end)
                }
                context.stroke(path, with: .color(strokeColor), style: strokeStyle)

                if content.strokeType == .arrow, let cp = content.controlPoint {
                    let ctrl = CGPoint(x: cp.x * size.width, y: cp.y * size.height)
                    drawArrowHead(context: context, end: end, controlPoint: ctrl,
                                  color: strokeColor, lineWidth: content.strokeWidth)
                }
            }
            // Canvas 尺寸比逻辑 frame 大 2*overflow，负偏移使布局位置不变
            .frame(width: geo.size.width + overflow * 2,
                   height: geo.size.height + overflow * 2)
            .offset(x: -overflow, y: -overflow)
        }
    }

    private func drawArrowHead(context: GraphicsContext, end: CGPoint, controlPoint: CGPoint,
                               color: Color, lineWidth: CGFloat) {
        let arrowSize: CGFloat = max(10, lineWidth * 4)
        let dx = end.x - controlPoint.x
        let dy = end.y - controlPoint.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return }
        let angle = atan2(dy, dx)
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(
            x: end.x - arrowSize * cos(angle - .pi / 6),
            y: end.y - arrowSize * sin(angle - .pi / 6)
        ))
        head.addLine(to: CGPoint(
            x: end.x - arrowSize * cos(angle + .pi / 6),
            y: end.y - arrowSize * sin(angle + .pi / 6)
        ))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }

    // MARK: - 选中控制点层

    private var controlPointsLayer: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                controlDot(at: CGPoint(x: content.startPoint.x * w,
                                       y: content.startPoint.y * h))
                controlDot(at: CGPoint(x: content.endPoint.x * w,
                                       y: content.endPoint.y * h))
                if content.strokeType == .arrow, let cp = content.controlPoint {
                    controlDot(at: CGPoint(x: cp.x * w, y: cp.y * h),
                               color: .orange)
                }
            }
        }
    }

    private func controlDot(at point: CGPoint, color: Color = .blue) -> some View {
        Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(color, lineWidth: 1.5))
            .frame(width: 10, height: 10)
            .position(point)
    }

    // MARK: - 颜色解析

    private func resolveColor(_ str: String) -> Color {
        NoteColorPickerPopover.colorFromString(str)
    }
}
