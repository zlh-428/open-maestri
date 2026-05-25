import SwiftUI
import AppKit

struct FreehandNodeSwiftUIView: View {
    let nodeId: UUID
    let content: FreehandContent
    let isSelected: Bool
    let zoom: CGFloat
    var onContentChange: ((FreehandContent) -> Void)?
    var onClose: ((UUID) -> Void)?

    var body: some View {
        ZStack {
            freehandCanvas
            if isSelected {
                controlPointsLayer
            }
        }
        .rotationEffect(Angle(radians: content.rotation))
        .allowsHitTesting(false)
    }

    // MARK: - 渲染主体

    private var freehandCanvas: some View {
        Canvas { context, size in
            guard content.points.count >= 2 else { return }

            let pts = content.points.map {
                CGPoint(x: $0.x * size.width, y: $0.y * size.height)
            }

            let path: Path
            if pts.count > 3 {
                path = catmullRomPath(pts)
            } else {
                var p = Path()
                p.move(to: pts[0])
                for pt in pts.dropFirst() { p.addLine(to: pt) }
                path = p
            }

            let color = resolveColor(content.strokeColor).opacity(content.opacity)
            let style = StrokeStyle(lineWidth: content.strokeWidth,
                                    lineCap: .round, lineJoin: .round)
            context.stroke(path, with: .color(color), style: style)
        }
    }

    private func catmullRomPath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: pts[0])
        for i in 0..<pts.count - 1 {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]
            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6,
                              y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6,
                              y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return path
    }

    // MARK: - 选中控制点层（8个 resize 控制点；旋转手柄暂不显示，待旋转交互实现后启用）

    private var controlPointsLayer: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r: CGFloat = 4
            ZStack {
                if content.rotation == 0 {
                    controlDot(at: CGPoint(x: 0,   y: 0),   r: r)
                    controlDot(at: CGPoint(x: w,   y: 0),   r: r)
                    controlDot(at: CGPoint(x: 0,   y: h),   r: r)
                    controlDot(at: CGPoint(x: w,   y: h),   r: r)
                    controlDot(at: CGPoint(x: w/2, y: 0),   r: r)
                    controlDot(at: CGPoint(x: w/2, y: h),   r: r)
                    controlDot(at: CGPoint(x: 0,   y: h/2), r: r)
                    controlDot(at: CGPoint(x: w,   y: h/2), r: r)
                }
                // 旋转手柄暂不显示，待旋转交互实现后启用
            }
        }
    }

    private func controlDot(at point: CGPoint, r: CGFloat) -> some View {
        Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(Color.blue, lineWidth: 1.5))
            .frame(width: r * 2, height: r * 2)
            .position(point)
    }

    // MARK: - 颜色解析

    private func resolveColor(_ str: String) -> Color {
        NoteColorPickerPopover.colorFromString(str)
    }
}
