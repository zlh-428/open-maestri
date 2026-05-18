import AppKit
import OSLog

/// 无限画布主 NSView
/// - 坐标系原点约 (9800, 8500)，即"无限"画布中心区域
/// - 通过 origin + zoom 变换映射到屏幕坐标
/// - 所有节点作为子 NSView 直接添加
final class CanvasViewportView: NSView {
    private let logger = Logger.make(category: "CanvasViewportView")

    // MARK: - 状态

    var canvasOrigin: CGPoint = Constants.canvasInitialOrigin {
        didSet {
            needsLayout = true
            needsDisplay = true
        }
    }

    var zoom: CGFloat = 1.0 {
        didSet {
            needsLayout = true
            needsDisplay = true
        }
    }

    /// 画布背景模式（从 Preferences 读取）
    var backgroundMode: String = "dotGrid" {
        didSet { needsDisplay = true }
    }

    /// 节点视图映射（nodeId → NSView）
    private(set) var nodeViews: [UUID: NSView] = [:]
    /// 反向映射（NSView 指针 → nodeId），用于 O(1) 反查（hitTest 热路径）
    var viewToNodeId: [ObjectIdentifier: UUID] = [:]

    /// 当前选中的节点 ID 集合
    var selectedNodeIds: Set<UUID> = [] {
        didSet {
            updateSelectionVisuals()
            reportSelectionChange()
        }
    }

    // MARK: - 回调

    var onViewportChanged: ((CGPoint, CGFloat) -> Void)?
    var onDeleteSelectedNodes: (() -> Void)?
    var onFocusSelectedNode: (() -> Void)?
    var onNodeJumpNumbersRequested: ((Bool) -> Void)? // true=显示, false=隐藏
    /// 选中节点变化时回调（选中 ID 集合, 第一个选中节点的屏幕 frame or nil）
    var onSelectionChanged: ((Set<UUID>, CGRect?) -> Void)?

    // MARK: - 连线工具状态
    /// 连线起点节点 ID（nil = 未开始连线）
    var connectingFromNodeId: UUID? = nil {
        didSet { needsDisplay = true }
    }
    /// 连线时鼠标当前屏幕坐标（用于绘制临时连线）
    var connectionDragPoint: CGPoint? = nil
    /// 连线完成回调（传入两个节点 UUID，调用者判断类型）
    var onConnectionCreated: ((UUID, UUID) -> Void)? = nil

    /// 是否处于连线工具激活状态（由 CanvasViewportRepresentable 根据 isConnecting 设置）
    var isInConnectingMode: Bool = false {
        didSet {
            if isInConnectingMode { activateConnectionMode() }
            else { deactivateConnectionMode() }
        }
    }

    /// 外部激活连线模式（由 CanvasViewportRepresentable 在 isConnecting=true 时调用）
    func activateConnectionMode() {
        connectionDragPoint = nil
        needsDisplay = true
        for ta in trackingAreas { removeTrackingArea(ta) }
        addTrackingArea(makeTrackingArea())
        NSCursor.crosshair.set()
    }

    func deactivateConnectionMode() {
        connectingFromNodeId = nil
        connectionDragPoint = nil
        needsDisplay = true
        NSCursor.arrow.set()
    }

    /// 节点内容类型查询（由 CanvasNodeRenderer 在创建节点后注册）
    var nodeContentTypes: [UUID: String] = [:]  // nodeId → "terminal"|"stickyNote"|"portal"|"fileTree"

    // MARK: - 初始化

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        canDrawConcurrently = true
        allowedTouchTypes = [.indirect, .direct]
        registerDragTypes()
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        let nc = NotificationCenter.default
        notificationObservers.append(
            nc.addObserver(forName: .canvasJumpToOrigin, object: nil, queue: .main) { [weak self] notif in
                guard let self, let target = notif.userInfo?["origin"] as? CGPoint else { return }
                self.animateOriginTo(target)
            }
        )
        notificationObservers.append(
            nc.addObserver(forName: .canvasZoomIn, object: nil, queue: .main) { [weak self] _ in
                self?.zoomCanvas(delta: +Constants.canvasZoomStep)
            }
        )
        notificationObservers.append(
            nc.addObserver(forName: .canvasZoomOut, object: nil, queue: .main) { [weak self] _ in
                self?.zoomCanvas(delta: -Constants.canvasZoomStep)
            }
        )
        notificationObservers.append(
            nc.addObserver(forName: .canvasZoomReset, object: nil, queue: .main) { [weak self] _ in
                self?.zoomCanvas(toAbsolute: 1.0)
            }
        )
        notificationObservers.append(
            nc.addObserver(forName: .toggleCanvasZoom, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                let target: CGFloat = abs(zoom - 1.0) < 0.05 ? 0.5 : 1.0
                self.zoomCanvas(toAbsolute: target)
            }
        )
    }

    /// 平滑动画跳转到指定画布原点（供 Minimap 点击等外部调用）
    func animateOriginTo(_ target: CGPoint, duration: TimeInterval = 0.3) {
        animateOrigin(from: canvasOrigin, to: target, startTime: CACurrentMediaTime(), duration: duration)
    }

    // MARK: - 第一响应者

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 确保成为第一响应者以接收手势事件（magnify/scrollWheel）
        // 只在 window 没有 attached sheet 时才抢焦点，避免 Sheet 弹出期间键盘事件被错误路由
        if window?.attachedSheet == nil {
            window?.makeFirstResponder(self)
        }
        installScrollEventMonitor()
    }

    // MARK: - 滚动事件路由（Local Event Monitor）

    /// 通过 local event monitor 拦截 scrollWheel / magnify 事件
    /// 逻辑：如果鼠标在某个**未选中**节点上，将事件重定向给画布（自己）
    /// 如果鼠标在**选中**节点上，让事件正常传递给节点内容（终端滚动等）
    /// 如果鼠标在空白区域，正常传递给画布
    private var scrollMonitor: Any?
    var notificationObservers: [NSObjectProtocol] = []

    private func installScrollEventMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self else { return event }
            return self.routeScrollEvent(event)
        }
    }

    private func routeScrollEvent(_ event: NSEvent) -> NSEvent? {
        guard let myWindow = self.window else { return event }
        if let eventWindow = event.window, eventWindow !== myWindow { return event }

        // 用 hitTest 判断事件是否发生在本视图或其子视图上
        let locInWindow = event.locationInWindow
        let hitView = myWindow.contentView?.hitTest(locInWindow)
        let isInCanvas = hitView != nil && (hitView === self || hitView?.isDescendant(of: self) == true)
        guard isInCanvas else { return event }

        if event.type == .magnify || event.type == .scrollWheel {
            // 判断鼠标是否悬停在某个选中节点上
            let hoveredNodeId = nodeIdForHitView(hitView)
            let isOverSelectedNode = hoveredNodeId.map { selectedNodeIds.contains($0) } ?? false

            if isOverSelectedNode, event.type == .scrollWheel,
               let hId = hoveredNodeId,
               let nodeView = nodeViews[hId] as? BaseNodeView {
                // 鼠标在选中节点上 + scrollWheel：手动转发给节点内容区域，
                // 然后吞掉事件（return nil），确保画布不再收到此 scroll
                nodeView.contentView.scrollWheel(with: event)
                return nil
            }

            // 其余情况（空白区域 / 未选中节点 / magnify）：由画布统一处理
            self.handle(scrollOrMagnify: event)
            return nil
        }

        return event
    }

    private func handle(scrollOrMagnify event: NSEvent) {
        if event.type == .magnify {
            magnify(with: event)
        } else {
            scrollWheel(with: event)
        }
    }

    /// 在视图树中递归做 hitTest，point 为相对于 root 的本地坐标
    private func deepHitTest(in root: NSView, at point: CGPoint) -> NSView? {
        guard root.bounds.contains(point), !root.isHidden, root.alphaValue > 0 else { return nil }
        for sub in root.subviews.reversed() {
            let subLocal = root.convert(point, to: sub)
            if let hit = deepHitTest(in: sub, at: subLocal) {
                return hit
            }
        }
        return root
    }

    /// 从视图（或其子视图）反查所属节点 ID（O(1) 直查 + O(n) 祖先降级）
    private func nodeIdForHitView(_ hitView: NSView?) -> UUID? {
        nodeId(for: hitView)
    }


    deinit {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
        animationTimer?.invalidate()
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - 坐标转换

    func canvasToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - canvasOrigin.x) * zoom,
            y: (point.y - canvasOrigin.y) * zoom
        )
    }

    func screenToCanvas(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x / zoom + canvasOrigin.x,
            y: point.y / zoom + canvasOrigin.y
        )
    }

    func canvasRectToScreen(_ rect: CGRect) -> CGRect {
        let origin = canvasToScreen(rect.origin)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: rect.width * zoom,
            height: rect.height * zoom
        )
    }

    func screenRectToCanvas(_ rect: CGRect) -> CGRect {
        let origin = screenToCanvas(rect.origin)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: rect.width / zoom,
            height: rect.height / zoom
        )
    }

    // MARK: - 布局

    override func layout() {
        super.layout()
        // 重新应用所有节点的位置和缩放变换（zoom/origin 变化时）
        // 跳过正在拖动的节点——其 frame 由 mouseDragged 直接维护，避免双重更新导致闪烁
        let draggedIds: Set<UUID> = isBatchDragging ? Set(batchDragStartFrames.keys) : (draggingNodeId.map { [$0] } ?? [])
        for (id, view) in nodeViews {
            if draggedIds.contains(id) { continue }
            if let canvasFrame = nodeCanvasFrames[id] {
                // frame = 缩放后的屏幕尺寸，bounds = 画布原始尺寸
                view.frame = canvasRectToScreen(canvasFrame)
                view.setBoundsSize(canvasFrame.size)
            }
        }
    }

    /// 保存每个节点的画布坐标（供 layout 时重算屏幕坐标）
    var nodeCanvasFrames: [UUID: CGRect] = [:]

    // MARK: - 节点管理

    func addNodeView(_ view: NSView, id: UUID, canvasFrame: CGRect) {
        nodeViews[id] = view
        viewToNodeId[ObjectIdentifier(view)] = id
        addSubview(view)
        updateNodeFrame(id: id, canvasFrame: canvasFrame)
    }

    func removeNodeView(id: UUID) {
        if let view = nodeViews[id] {
            viewToNodeId.removeValue(forKey: ObjectIdentifier(view))
            view.removeFromSuperview()
        }
        nodeViews.removeValue(forKey: id)
        nodeCanvasFrames.removeValue(forKey: id)
    }

    func updateNodeFrame(id: UUID, canvasFrame: CGRect) {
        guard let view = nodeViews[id] else { return }
        // 拖动期间不允许外部覆盖被拖动节点的 frame
        if draggingNodeId != nil {
            let isDragged = (id == draggingNodeId) || batchDragStartFrames.keys.contains(id)
            if isDragged { return }
        }
        nodeCanvasFrames[id] = canvasFrame
        // frame = 缩放后屏幕尺寸，bounds = 画布原始尺寸（子视图以原始比例 layout）
        view.frame = canvasRectToScreen(canvasFrame)
        view.setBoundsSize(canvasFrame.size)
    }

    override func hitTest(_ point: CGPoint) -> NSView? {
        for view in subviews.reversed() {
            guard nodeViews.values.contains(where: { $0 === view }) else {
                if let hit = view.hitTest(convert(point, to: view)) {
                    return hit
                }
                continue
            }
            // frame 已是缩放后的屏幕尺寸，直接做 contains 检测
            guard view.frame.contains(point) else { continue }
            // 将屏幕坐标映射回节点 bounds 坐标系（bounds 是画布原始尺寸）
            let localX = (point.x - view.frame.minX) / zoom
            let localY = (point.y - view.frame.minY) / zoom
            return deepHitTest(in: view, at: CGPoint(x: localX, y: localY))
        }
        return super.hitTest(point)
    }

    // MARK: - 选中视觉更新

    private func updateSelectionVisuals() {
        for (id, view) in nodeViews {
            let selected = selectedNodeIds.contains(id)
            if let tv = view as? TerminalNodeView {
                tv.isSelected = selected
            }
            if let baseNode = view as? BaseNodeView {
                baseNode.isNodeSelected = selected
                if selected && selectedNodeIds.count == 1 {
                    baseNode.onFocusRequested?()
                }
            }
        }
    }

    private func reportSelectionChange() {
        guard let callback = onSelectionChanged else { return }
        if let firstId = selectedNodeIds.first, let view = nodeViews[firstId] {
            callback(selectedNodeIds, view.frame)
        } else {
            callback(selectedNodeIds, nil)
        }
    }

    // MARK: - 节点拖动状态（由 CanvasDragHandler 扩展使用）

    var draggingNodeId: UUID? = nil
    var dragStartCanvasMouse: CGPoint? = nil
    var dragStartCanvasFrame: CGRect? = nil
    /// 上次触发磁力吸附的状态（用于检测从无→有触发 haptic）
    var lastSnapActive: Bool = false
    /// 上次网格吸附后的坐标（用于检测是否跨格，nil = 拖动尚未开始）
    var lastSnappedGridOrigin: CGPoint? = nil
    /// 当前拖动中的参考线（用于绘制）
    var dragGuidelines: [GuideLine] = [] {
        didSet { needsDisplay = true }
    }
    /// 批量拖动：所有被拖动节点的初始 frame（不含主节点）
    var batchDragStartFrames: [UUID: CGRect] = [:]
    /// 是否正在进行批量拖动
    var isBatchDragging: Bool { !batchDragStartFrames.isEmpty }
    /// 拖动过程中是否发生了实际位移（用于区分点击和拖动）
    var didDragMove = false

    var onNodeDragEnded: ((UUID, CGRect) -> Void)?
    var onBatchNodeDragEnded: (([UUID: CGRect]) -> Void)?

    // MARK: - 平移模式状态（由 CanvasInputHandler 扩展使用）

    var isPanMode = false
    var isSpaceHeld = false
    var spaceDragStartOrigin: CGPoint?
    var spaceDragStartMouse: CGPoint?

    // MARK: - 框选状态（由 CanvasDragHandler 扩展使用）

    var selectionStartPoint: CGPoint?
    var selectionCurrentPoint: CGPoint?

    var selectionRect: CGRect? {
        guard let start = selectionStartPoint, let current = selectionCurrentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    // MARK: - 节点绘制模式状态（由 CanvasDragHandler 扩展使用）

    var isInDrawingMode: Bool = false
    var drawingNodeType: String = "terminal"
    var drawingStartPoint: CGPoint?
    var drawingCurrentPoint: CGPoint?
    var onNodeDrawn: ((String, CGRect) -> Void)?

    // MARK: - 文件拖放状态（由 CanvasDragHandler 扩展使用）

    var onFilesDropped: (([String], CGPoint) -> Void)?
    var onFilesDroppedOnNode: (([String], UUID) -> Void)?
    var dropTargetNodeId: UUID?

    // MARK: - 动画定时器（由 CanvasInputHandler 扩展使用）

    var animationTimer: Timer?

    // MARK: - 变更通知

    func notifyViewportChanged() {
        onViewportChanged?(canvasOrigin, zoom)
    }

    // MARK: - 背景绘制

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 先绘制背景
        switch backgroundMode {
        case "dotGrid":
            drawLineGrid(in: dirtyRect)
        case "solid":
            NSColor(white: 0.98, alpha: 1).setFill()
            dirtyRect.fill()
        case "transparent":
            NSColor.clear.setFill()
            dirtyRect.fill()
        default:
            drawLineGrid(in: dirtyRect)
        }

        // 再绘制前景覆盖物（连线、绘制矩形、框选矩形、磁力对齐参考线）
        drawTemporaryConnection()
        drawDrawingRect()
        drawSelectionRect()
        drawSnapGuidelines()
    }

    /// 白色背景 + 浅灰色网格线（对标 Maestri 产品样式）
    private func drawLineGrid(in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 白色背景填充
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(rect)

        let gridSpacing: CGFloat = Constants.canvasGridSpacing * zoom
        let lineColor = Constants.canvasGridLineColor.cgColor
        let lineWidth = Constants.canvasGridLineWidth

        // 计算画布偏移以保持网格与画布坐标对齐
        let offsetX = -(canvasOrigin.x * zoom).truncatingRemainder(dividingBy: gridSpacing)
        let offsetY = -(canvasOrigin.y * zoom).truncatingRemainder(dividingBy: gridSpacing)

        ctx.setStrokeColor(lineColor)
        ctx.setLineWidth(lineWidth)

        // 批量绘制垂直线
        let startX = rect.minX - rect.minX.truncatingRemainder(dividingBy: gridSpacing) + offsetX
        var x = startX
        while x <= rect.maxX {
            ctx.move(to: CGPoint(x: x, y: rect.minY))
            ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += gridSpacing
        }

        // 批量绘制水平线
        let startY = rect.minY - rect.minY.truncatingRemainder(dividingBy: gridSpacing) + offsetY
        var y = startY
        while y <= rect.maxY {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += gridSpacing
        }

        ctx.strokePath()
    }
}

// MARK: - Comparable clamped

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
