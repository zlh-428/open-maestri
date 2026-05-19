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

    /// 节点 SwiftUI 容器（由 CanvasNodeRenderer 创建后注册，供 hitTestCanvas 使用）
    weak var nodesHostingView: CanvasNodesView?

    /// 当前画布节点列表（由 CanvasNodeRenderer.sync() 同步，供 hitTestCanvas 使用）
    var currentNodes: [CanvasNode] = []

    /// option+拖拽复制节点回调
    var onDuplicateNode: ((UUID) -> Void)?

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

        // 用画布坐标系的 frame 判断鼠标是否在本视图（画布）范围内
        // 避免依赖 hitTest + isDescendant（NSHostingView 的 flipped 视图会导致误判）
        let locInCanvas = convert(event.locationInWindow, from: nil)
        guard bounds.contains(locInCanvas) else { return event }

        // magnify 始终由画布处理（捏合缩放画布视口）
        if event.type == .magnify {
            self.magnify(with: event)
            return nil
        }
        guard event.type == .scrollWheel else { return event }

        // 用 frame 直接判断鼠标是否在某个选中节点的内容区内
        // 这比 hitView.isDescendant 更可靠：不受子视图 isFlipped 或 overlay 影响
        let locInWindow = event.locationInWindow
        for selectedId in selectedNodeIds {
            guard let nodeView = nodeViews[selectedId] as? BaseNodeView else { continue }
            // 用屏幕坐标（nodeView.frame 已是缩放后的屏幕坐标）做 frame 命中测试
            guard nodeView.frame.contains(locInCanvas) else { continue }
            // 进一步确认：鼠标在 contentView 区域内（排除 header、resize 边缘）
            let localInContent = nodeView.contentView.convert(locInWindow, from: nil)
            guard nodeView.contentView.bounds.contains(localInContent) else { continue }
            // 在 contentView 子视图树中找可滚动目标
            if let target = findScrollTarget(in: nodeView.contentView, at: localInContent) {
                target.scrollWheel(with: event)
                return nil
            }
            // 找不到可滚动目标（Note 内容未溢出等情况）：回退给画布平移，不要吃掉事件
            break
        }

        // 画布处理：平移
        self.scrollWheel(with: event)
        return nil
    }

    /// 在视图树（以 root 为根，point 为 root 的 bounds 坐标）中，
    /// 查找最合适的滚动目标：
    ///  1. NSScrollView（最优先，包括 Terminal 内的 scrollView）
    ///  2. 非标准自定义 NSView（如 SwiftTerm TerminalView）
    /// 故意跳过 NSHostingView（SwiftUI 容器，不可靠）。
    private func findScrollTarget(in root: NSView, at point: CGPoint) -> NSView? {
        guard root.bounds.contains(point), !root.isHidden, root.alphaValue > 0 else { return nil }
        // NSScrollView 直接命中（最高优先级，不再深入）
        if root is NSScrollView { return root }
        // NSHostingView：排除，不递归其内部（SwiftUI 视图中的 NSScrollView 不可直接控制）
        let rootTypeName = String(describing: type(of: root))
        if rootTypeName.contains("HostingView") || rootTypeName.contains("Hosting") { return nil }
        // 递归子视图（深度优先）
        for sub in root.subviews.reversed() {
            let subPoint = root.convert(point, to: sub)
            if let found = findScrollTarget(in: sub, at: subPoint) {
                return found
            }
        }
        // 非标准 NSView（如 SwiftTerm TerminalView，type != NSView && != NSClipView）
        if type(of: root) != NSView.self && !(root is NSClipView) {
            return root
        }
        return nil
    }

    private func handle(scrollOrMagnify event: NSEvent) {
        if event.type == .magnify {
            magnify(with: event)
        } else {
            scrollWheel(with: event)
        }
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
        // 跳过正在被交互的节点（其 frame 由 CanvasInteractionHandler 直接维护）
        let skipIds: Set<UUID>
        switch interaction {
        case .draggingNode(let id, _, _):
            skipIds = [id]
        case .batchDragging(let frames, _, _):
            skipIds = Set(frames.keys)
        case .resizingNode(let id, _, _, _):
            skipIds = [id]
        case .mayDragNode(let id, _, _, _):
            skipIds = [id]
        default:
            skipIds = []
        }
        for (id, view) in nodeViews {
            if skipIds.contains(id) { continue }
            if let canvasFrame = nodeCanvasFrames[id] {
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
        // 拖动/resize 期间不允许外部覆盖被交互节点的 frame
        switch interaction {
        case .draggingNode(let did, _, _) where did == id: return
        case .batchDragging(let frames, _, _) where frames.keys.contains(id): return
        case .resizingNode(let rid, _, _, _) where rid == id: return
        case .mayDragNode(let mid, _, _, _) where mid == id: return
        default: break
        }
        nodeCanvasFrames[id] = canvasFrame
        view.frame = canvasRectToScreen(canvasFrame)
        view.setBoundsSize(canvasFrame.size)
    }


    // MARK: - 选中视觉更新

    private func updateSelectionVisuals() {
        NotificationCenter.default.post(
            name: .canvasSelectionChanged,
            object: nil,
            userInfo: ["selectedIds": selectedNodeIds]
        )
    }

    private func reportSelectionChange() {
        guard let callback = onSelectionChanged else { return }
        if let firstId = selectedNodeIds.first, let view = nodeViews[firstId] {
            callback(selectedNodeIds, view.frame)
        } else {
            callback(selectedNodeIds, nil)
        }
    }

    // MARK: - 统一交互状态机

    /// 当前画布交互状态（替换所有散落的拖动/选择/resize 状态变量）
    var interaction: CanvasInteraction = .idle

    /// 拖动期间用于 drag guideline 绘制
    var dragGuidelines: [GuideLine] = [] {
        didSet { needsDisplay = true }
    }

    // 以下保留（与状态机无关，供外部回调）
    var onNodeDragEnded: ((UUID, CGRect) -> Void)?
    var onBatchNodeDragEnded: (([UUID: CGRect]) -> Void)?
    /// resize 结束时回调（替换 onFrameChanged 的旧机制）
    var onNodeResizeEnded: ((UUID, CGRect) -> Void)?

    // MARK: - 平移模式状态（由 CanvasInputHandler 扩展使用）

    var isPanMode = false
    var isSpaceHeld = false

    // MARK: - 节点绘制模式状态

    var isInDrawingMode: Bool = false
    var drawingNodeType: String = "terminal"
    var onNodeDrawn: ((String, CGRect) -> Void)?

    // MARK: - 框选/绘制/snap 辅助状态（由 CanvasInteractionHandler 维护）

    /// 框选当前鼠标位置（仅在 interaction == .marquee 时有效）
    var marqueeCurrentPoint: CGPoint?
    /// 节点绘制模式当前鼠标位置
    var drawingCurrentPoint: CGPoint?
    /// 磁吸/网格 snap 辅助状态
    var lastSnapActive: Bool = false
    var lastSnappedGridOrigin: CGPoint? = nil

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
