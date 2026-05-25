import SwiftUI
import AppKit

struct ShapeNodeSwiftUIView: View {
    let nodeId: UUID
    let content: ShapeContent
    let isSelected: Bool
    let zoom: CGFloat
    var onContentChange: ((ShapeContent) -> Void)?
    var onClose: ((UUID) -> Void)?

    @State private var isEditing = false
    @State private var editText: String = ""

    var body: some View {
        ZStack {
            // 图形层
            shapeCanvas

            // 文字层
            if !content.text.isEmpty || isEditing {
                textLayer
            }

            // 选中控制点层（旋转 = 0 时才显示 resize 控制点；旋转后只显示旋转手柄）
            if isSelected {
                controlPointsLayer
            }
        }
        .rotationEffect(Angle(radians: content.rotation))
        .onReceive(
            NotificationCenter.default.publisher(for: .shapeNodeShouldBeginEditing)
        ) { notif in
            guard let id = notif.userInfo?["nodeId"] as? UUID, id == nodeId else { return }
            editText = content.text
            isEditing = true
        }
        .allowsHitTesting(false)
    }

    // MARK: - 图形层

    private var shapeCanvas: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let path = Path(roundedRect: rect, cornerRadius: 0)

            // 填充
            switch content.fillStyle {
            case .solid:
                if let color = Color(hex: content.fillColor) {
                    context.fill(path, with: .color(color))
                }
            case .none:
                break
            case .hatched:
                if let color = Color(hex: content.fillColor) {
                    context.fill(path, with: .color(color.opacity(0.15)))
                }
                context.drawLayer { ctx in
                    ctx.clipToLayer { c in
                        c.fill(path, with: .color(.black))
                    }
                    drawHatchLines(context: ctx, size: size, angle: 45, color: content.strokeColor)
                }
            case .crossHatched:
                if let color = Color(hex: content.fillColor) {
                    context.fill(path, with: .color(color.opacity(0.15)))
                }
                context.drawLayer { ctx in
                    ctx.clipToLayer { c in
                        c.fill(path, with: .color(.black))
                    }
                    drawHatchLines(context: ctx, size: size, angle: 45, color: content.strokeColor)
                    drawHatchLines(context: ctx, size: size, angle: -45, color: content.strokeColor)
                }
            }

            // 边框
            let strokeColor = Color(hex: content.strokeColor) ?? .blue
            let strokeStyle: StrokeStyle
            switch content.strokeStyle {
            case .solid:
                strokeStyle = StrokeStyle(lineWidth: content.strokeWidth)
            case .dashed:
                strokeStyle = StrokeStyle(lineWidth: content.strokeWidth, dash: [8, 4])
            case .dotted:
                strokeStyle = StrokeStyle(lineWidth: content.strokeWidth, dash: [2, 4])
            }
            context.stroke(path, with: .color(strokeColor), style: strokeStyle)
        }
    }

    private func drawHatchLines(context: GraphicsContext, size: CGSize, angle: CGFloat, color: String) {
        let lineColor = Color(hex: color) ?? .blue
        let spacing: CGFloat = 8
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        let count = Int(diagonal / spacing) + 2
        let cx = size.width / 2
        let cy = size.height / 2
        let rad = angle * .pi / 180

        for i in -count...count {
            let offset = CGFloat(i) * spacing
            var path = Path()
            let x0 = cx + offset * cos(rad + .pi/2) - diagonal * cos(rad)
            let y0 = cy + offset * sin(rad + .pi/2) - diagonal * sin(rad)
            let x1 = cx + offset * cos(rad + .pi/2) + diagonal * cos(rad)
            let y1 = cy + offset * sin(rad + .pi/2) + diagonal * sin(rad)
            path.move(to: CGPoint(x: x0, y: y0))
            path.addLine(to: CGPoint(x: x1, y: y1))
            context.stroke(path, with: .color(lineColor.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1))
        }
    }

    // MARK: - 文字层

    @ViewBuilder
    private var textLayer: some View {
        if isEditing {
            ShapeTextEditor(
                text: $editText,
                fontSize: content.fontSize,
                onCommit: {
                    // Notify WorkspaceCanvasView to persist text change
                    NotificationCenter.default.post(
                        name: .shapeNodeTextDidEndEditing,
                        object: nil,
                        userInfo: ["nodeId": nodeId, "text": editText]
                    )
                    isEditing = false
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
        } else {
            Text(content.text)
                .font(.system(size: content.fontSize))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: content.strokeColor) ?? .primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
        }
    }

    // MARK: - 控制点层

    private var controlPointsLayer: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r: CGFloat = 4   // 控制点半径（直径 8pt）

            ZStack {
                // 旋转=0 时才显示 resize 控制点（旋转后坐标系复杂，暂不支持）
                if content.rotation == 0 {
                    // 四角
                    controlDot(at: CGPoint(x: 0, y: 0), r: r)
                    controlDot(at: CGPoint(x: w, y: 0), r: r)
                    controlDot(at: CGPoint(x: 0, y: h), r: r)
                    controlDot(at: CGPoint(x: w, y: h), r: r)
                    // 四边中点
                    controlDot(at: CGPoint(x: w/2, y: 0), r: r)
                    controlDot(at: CGPoint(x: w/2, y: h), r: r)
                    controlDot(at: CGPoint(x: 0, y: h/2), r: r)
                    controlDot(at: CGPoint(x: w, y: h/2), r: r)
                }

                // 旋转手柄：始终显示
                rotationHandle(w: w)
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

    private func rotationHandle(w: CGFloat) -> some View {
        let lineLength: CGFloat = 20
        let dotR: CGFloat = 5

        return ZStack {
            // 连接线
            Rectangle()
                .fill(Color.blue)
                .frame(width: 1, height: lineLength)
                .position(x: w/2, y: -(lineLength/2))

            // 圆点
            Circle()
                .fill(.white)
                .overlay(Circle().strokeBorder(Color.blue, lineWidth: 1.5))
                .frame(width: dotR * 2, height: dotR * 2)
                .position(x: w/2, y: -lineLength - dotR)
        }
    }
}

// MARK: - 文字编辑器（NSTextField overlay）

private struct ShapeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let onCommit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.isEditable = true
        tf.isSelectable = true
        tf.alignment = .center
        tf.font = .systemFont(ofSize: fontSize)
        tf.delegate = context.coordinator
        tf.focusRingType = .none
        tf.stringValue = text
        DispatchQueue.main.async {
            tf.window?.makeFirstResponder(tf)
            tf.selectAll(nil)
        }
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.font = .systemFont(ofSize: fontSize)
        if nsView.currentEditor() == nil {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: ShapeTextEditor
        init(parent: ShapeTextEditor) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let tf = obj.object as? NSTextField {
                parent.text = tf.stringValue
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
            parent.onCommit()
        }
    }
}
