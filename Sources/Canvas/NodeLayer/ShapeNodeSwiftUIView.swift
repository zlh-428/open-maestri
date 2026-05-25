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
    // 用 content.text 初始化，避免有文字的历史节点首次渲染为空
    @State private var editText: String

    init(
        nodeId: UUID,
        content: ShapeContent,
        isSelected: Bool,
        zoom: CGFloat,
        onContentChange: ((ShapeContent) -> Void)? = nil,
        onClose: ((UUID) -> Void)? = nil
    ) {
        self.nodeId = nodeId
        self.content = content
        self.isSelected = isSelected
        self.zoom = zoom
        self.onContentChange = onContentChange
        self.onClose = onClose
        // @State 的初始值只在视图首次创建时生效
        self._editText = State(initialValue: content.text)
    }

    var body: some View {
        ZStack {
            // 图形层
            shapeCanvas

            // ShapeTextEditor 始终存在，NSTextView 始终注册在 ShapeTextViewRegistry。
            // isEditing 控制 isEditable/isSelectable，非编辑态下文字只读显示。
            // 这样 mouseDown 时无论有无文字都能直接转发坐标修正事件，无需 Placeholder。
            ShapeTextEditor(
                text: $editText,
                nodeId: nodeId,
                fontSize: content.fontSize,
                textColor: NSColor(textColor),
                isEditing: isEditing,
                onCommit: {
                    NotificationCenter.default.post(
                        name: .shapeNodeTextDidEndEditing,
                        object: nil,
                        userInfo: ["nodeId": nodeId, "text": editText]
                    )
                    isEditing = false
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 选中控制点层
            if isSelected {
                controlPointsLayer
            }
        }
        .rotationEffect(Angle(radians: content.rotation))
        .onReceive(
            NotificationCenter.default.publisher(for: .shapeNodeShouldBeginEditing)
        ) { notif in
            guard let id = notif.userInfo?["nodeId"] as? UUID, id == nodeId else { return }
            let selectAll = notif.userInfo?["selectAll"] as? Bool ?? false
            editText = content.text
            isEditing = true
            if selectAll {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    ShapeTextViewRegistry.shared.textView(for: nodeId)?.selectAll(nil)
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .canvasNodeContentChanged)
        ) { notif in
            guard let id = notif.userInfo?["nodeId"] as? UUID, id == nodeId else { return }
            if !isEditing,
               let newContent = notif.userInfo?["content"] as? NodeContent,
               case .shape(let sc) = newContent {
                editText = sc.text
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - 颜色解析

    private func resolveColor(_ str: String) -> Color {
        NoteColorPickerPopover.colorFromString(str)
    }

    private var textColor: Color {
        let base = resolveColor(content.strokeColor)
        let ns = NSColor(base)
        let darkened = ns.blended(withFraction: 0.35, of: .black) ?? ns
        return Color(darkened)
    }

    // MARK: - 图形层

    private var shapeCanvas: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let path = Path(roundedRect: rect, cornerRadius: 0)

            let themeColor = resolveColor(content.strokeColor)

            switch content.fillStyle {
            case .solid:
                context.fill(path, with: .color(themeColor.opacity(0.3)))
            case .none:
                break
            case .hatched:
                context.fill(path, with: .color(themeColor.opacity(0.1)))
                context.drawLayer { ctx in
                    ctx.clipToLayer { c in c.fill(path, with: .color(.black)) }
                    drawHatchLines(context: ctx, size: size, angle: 45, color: content.strokeColor)
                }
            case .crossHatched:
                context.fill(path, with: .color(themeColor.opacity(0.1)))
                context.drawLayer { ctx in
                    ctx.clipToLayer { c in c.fill(path, with: .color(.black)) }
                    drawHatchLines(context: ctx, size: size, angle: 45, color: content.strokeColor)
                    drawHatchLines(context: ctx, size: size, angle: -45, color: content.strokeColor)
                }
            }

            let strokeColor = resolveColor(content.strokeColor)
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
        let lineColor = resolveColor(color)
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

    // MARK: - 控制点层

    private var controlPointsLayer: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r: CGFloat = 4

            ZStack {
                if content.rotation == 0 {
                    controlDot(at: CGPoint(x: 0, y: 0), r: r)
                    controlDot(at: CGPoint(x: w, y: 0), r: r)
                    controlDot(at: CGPoint(x: 0, y: h), r: r)
                    controlDot(at: CGPoint(x: w, y: h), r: r)
                    controlDot(at: CGPoint(x: w/2, y: 0), r: r)
                    controlDot(at: CGPoint(x: w/2, y: h), r: r)
                    controlDot(at: CGPoint(x: 0, y: h/2), r: r)
                    controlDot(at: CGPoint(x: w, y: h/2), r: r)
                }
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
            Rectangle()
                .fill(Color.blue)
                .frame(width: 1, height: lineLength)
                .position(x: w/2, y: -(lineLength/2))

            Circle()
                .fill(.white)
                .overlay(Circle().strokeBorder(Color.blue, lineWidth: 1.5))
                .frame(width: dotR * 2, height: dotR * 2)
                .position(x: w/2, y: -lineLength - dotR)
        }
    }
}

// MARK: - Shape NSTextView 全局注册表

final class ShapeTextViewRegistry {
    static let shared = ShapeTextViewRegistry()
    private var textViews: [UUID: NSTextView] = [:]
    private let lock = NSLock()
    private init() {}

    func register(nodeId: UUID, textView: NSTextView) {
        lock.lock(); defer { lock.unlock() }
        textViews[nodeId] = textView
    }

    func unregister(nodeId: UUID) {
        lock.lock(); defer { lock.unlock() }
        textViews.removeValue(forKey: nodeId)
    }

    func textView(for nodeId: UUID) -> NSTextView? {
        lock.lock(); defer { lock.unlock() }
        return textViews[nodeId]
    }
}

// MARK: - 文字编辑器

/// Shape 节点文字编辑器。始终渲染、始终注册 NSTextView。
/// - 非编辑态（isEditing=false）：isEditable=false，文字只读显示，透明背景。
/// - 编辑态（isEditing=true）：isEditable=true，接受键盘输入。
///
/// 由于 NSTextView 始终存在，CanvasInteractionHandler 的 mouseDown 路径永远能在
/// ShapeTextViewRegistry 中查到 tv，直接用 correctedWindowLocationForShapeTextView
/// 转发坐标修正后的事件，光标定位由 NSTextView 原生处理（与 Note 节点完全一致）。
private struct ShapeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let nodeId: UUID
    let fontSize: CGFloat
    let textColor: NSColor
    let isEditing: Bool
    let onCommit: () -> Void

    func makeNSView(context: Context) -> CenteredTextScrollView {
        let scrollView = CenteredTextScrollView()

        let tv = scrollView.documentView as! NSTextView
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: fontSize)
        tv.alignment = .center
        tv.textColor = textColor
        tv.delegate = context.coordinator
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        tv.string = text

        ShapeTextViewRegistry.shared.register(nodeId: nodeId, textView: tv)
        applyEditingState(tv: tv, isEditing: isEditing)
        return scrollView
    }

    func updateNSView(_ scrollView: CenteredTextScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        // 同步 coordinator.parent，确保 textDidEndEditing 回调持有最新闭包和绑定
        context.coordinator.parent = self
        tv.font = .systemFont(ofSize: fontSize)
        tv.textColor = textColor
        // isEditable 从 true→false 时，AppKit 会再次触发 textDidEndEditing。
        // 先把 delegate 置 nil 再改 isEditable，断开回调链，防止 onCommit 被重复调用。
        if tv.isEditable && !isEditing {
            tv.delegate = nil
            tv.isEditable = false
            tv.isSelectable = false
            tv.delegate = context.coordinator
        } else {
            applyEditingState(tv: tv, isEditing: isEditing)
        }
        // 非编辑焦点时同步外部内容变化
        if tv.window?.firstResponder !== tv && tv.string != text {
            tv.string = text
        }
        scrollView.recenterText()
    }

    static func dismantleNSView(_ scrollView: CenteredTextScrollView, coordinator: Coordinator) {
        ShapeTextViewRegistry.shared.unregister(nodeId: coordinator.nodeId)
    }

    func makeCoordinator() -> Coordinator { Coordinator(nodeId: nodeId, parent: self) }

    private func applyEditingState(tv: NSTextView, isEditing: Bool) {
        tv.isEditable = isEditing
        tv.isSelectable = isEditing
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let nodeId: UUID
        var parent: ShapeTextEditor

        init(nodeId: UUID, parent: ShapeTextEditor) {
            self.nodeId = nodeId
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            if let sv = tv.enclosingScrollView as? CenteredTextScrollView {
                sv.recenterText()
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onCommit()
        }
    }
}

// MARK: - 垂直居中 ScrollView

final class CenteredTextScrollView: NSScrollView {

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        hasVerticalScroller = false
        hasHorizontalScroller = false
        autohidesScrollers = true
        borderType = .noBorder
        drawsBackground = false

        let tv = NSTextView(frame: .zero)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        documentView = tv
    }

    func recenterText() {
        guard let tv = documentView as? NSTextView,
              let lm = tv.layoutManager,
              let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height
        let available = bounds.height
        let topInset = max(0, (available - used) / 2)
        tv.textContainerInset = NSSize(width: 4, height: topInset)
    }

    override func layout() {
        super.layout()
        recenterText()
    }
}
