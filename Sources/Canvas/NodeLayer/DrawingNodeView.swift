import AppKit

/// 画布手绘区域节点
/// 支持自由绘制笔画，右键菜单清除/撤销
final class DrawingNodeView: BaseNodeView {

    /// 已完成的笔画
    private var strokes: [DrawingStroke] = []
    /// 当前正在绘制的笔画点
    private var currentPoints: [CGPoint] = []
    /// 当前笔画颜色
    var strokeColor: String = "#000000"
    /// 当前笔画宽度
    var strokeWidth: CGFloat = 2

    /// 笔画变化回调（传回所有笔画）
    var onStrokesChanged: (([DrawingStroke]) -> Void)?

    /// 内嵌的绘图画布
    private let drawingCanvas = DrawingCanvasLayer()

    override func setup() {
        super.setup()

        // 白色背景 + 浅灰边框
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderColor = NSColor(white: 0.85, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 6

        // Header 使用浅色风格
        headerView.layer?.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor
        headerLabel.textColor = .labelColor
        headerLabel.font = .systemFont(ofSize: 12, weight: .medium)

        // 绘图层
        drawingCanvas.wantsLayer = true
        drawingCanvas.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.addSubview(drawingCanvas)
    }

    override func layout() {
        super.layout()
        drawingCanvas.frame = contentView.bounds
        drawingCanvas.needsDisplay = true
    }

    // MARK: - 配置

    func configure(strokes: [DrawingStroke], backgroundColor: String) {
        self.strokes = strokes
        drawingCanvas.strokes = strokes
        if let bgColor = NSColor(hex: backgroundColor) {
            drawingCanvas.layer?.backgroundColor = bgColor.cgColor
        }
        drawingCanvas.needsDisplay = true
    }

    // MARK: - 鼠标绘制

    override func mouseDown(with event: NSEvent) {
        let loc = drawingCanvas.convert(event.locationInWindow, from: nil)
        // 如果在 header 区域，走默认拖拽
        if loc.y > drawingCanvas.bounds.height {
            super.mouseDown(with: event)
            return
        }
        currentPoints = [loc]
    }

    override func mouseDragged(with event: NSEvent) {
        guard !currentPoints.isEmpty else {
            super.mouseDragged(with: event)
            return
        }
        let loc = drawingCanvas.convert(event.locationInWindow, from: nil)
        currentPoints.append(loc)
        drawingCanvas.currentStrokePoints = currentPoints
        drawingCanvas.currentStrokeColor = strokeColor
        drawingCanvas.currentStrokeWidth = strokeWidth
        drawingCanvas.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !currentPoints.isEmpty else {
            super.mouseUp(with: event)
            return
        }
        if currentPoints.count >= 2 {
            let stroke = DrawingStroke(
                points: currentPoints.map { [$0.x, $0.y] },
                color: strokeColor,
                width: strokeWidth
            )
            strokes.append(stroke)
            drawingCanvas.strokes = strokes
            onStrokesChanged?(strokes)
        }
        currentPoints = []
        drawingCanvas.currentStrokePoints = []
        drawingCanvas.needsDisplay = true
    }

    // MARK: - 右键菜单

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "撤销笔画", action: #selector(undoStroke), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "清除全部", action: #selector(clearAll), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "复制节点", action: #selector(duplicateDrawing), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "创建连接", action: #selector(startConnect), keyEquivalent: ""))
        menu.addItem(.separator())
        let lockItem = NSMenuItem(title: isLocked ? "解锁" : "锁定",
                                  action: #selector(toggleLock), keyEquivalent: "")
        menu.addItem(lockItem)
        menu.addItem(.separator())
        let closeItem = NSMenuItem(title: "删除", action: #selector(closeDrawing), keyEquivalent: "")
        let closeAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]
        closeItem.attributedTitle = NSAttributedString(string: "删除", attributes: closeAttrs)
        menu.addItem(closeItem)
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func undoStroke() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        drawingCanvas.strokes = strokes
        drawingCanvas.needsDisplay = true
        onStrokesChanged?(strokes)
    }

    @objc private func clearAll() {
        strokes.removeAll()
        drawingCanvas.strokes = strokes
        drawingCanvas.needsDisplay = true
        onStrokesChanged?(strokes)
    }

    @objc private func duplicateDrawing() { onDuplicate?() }
    @objc private func startConnect() { onConnect?() }
    @objc private func toggleLock() {
        isLocked = !isLocked
        onLockToggle?(isLocked)
    }
    @objc private func closeDrawing() { onClose?() }
}

// MARK: - 绘图画布层

/// 负责渲染笔画的 NSView
private final class DrawingCanvasLayer: NSView {
    var strokes: [DrawingStroke] = []
    var currentStrokePoints: [CGPoint] = []
    var currentStrokeColor: String = "#000000"
    var currentStrokeWidth: CGFloat = 2

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 绘制已完成的笔画
        for stroke in strokes {
            drawStroke(
                points: stroke.points.compactMap { arr -> CGPoint? in
                    guard arr.count >= 2 else { return nil }
                    return CGPoint(x: arr[0], y: arr[1])
                },
                color: NSColor(hex: stroke.color) ?? .black,
                width: stroke.width
            )
        }

        // 绘制当前正在绘制的笔画
        if !currentStrokePoints.isEmpty {
            drawStroke(
                points: currentStrokePoints,
                color: NSColor(hex: currentStrokeColor) ?? .black,
                width: currentStrokeWidth
            )
        }
    }

    private func drawStroke(points: [CGPoint], color: NSColor, width: CGFloat) {
        guard points.count >= 2 else { return }
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()

        path.move(to: points[0])
        for i in 1..<points.count {
            path.line(to: points[i])
        }
        path.stroke()
    }
}
