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
            backgroundView?.canvasOrigin = canvasOrigin
            drawingLayerView?.canvasOrigin = canvasOrigin
            drawingOverlayView?.canvasOrigin = canvasOrigin
            snapGuideView?.canvasOrigin = canvasOrigin
        }
    }

    var zoom: CGFloat = 1.0 {
        didSet {
            needsLayout = true
            needsDisplay = true
            backgroundView?.zoom = zoom
            drawingLayerView?.zoom = zoom
            drawingOverlayView?.zoom = zoom
            snapGuideView?.zoom = zoom
        }
    }

    /// 画布背景模式（从 Preferences 读取）
    var backgroundMode: String = "dotGrid" {
        didSet {
            backgroundView?.backgroundMode = backgroundMode
        }
    }

    // MARK: - 分层视图

    private var backgroundView: CanvasBackground?
    var drawingLayerView: DrawingLayerView?
    var drawingOverlayView: DrawingOverlayView?
    private(set) var snapGuideView: MagneticSnapGuideView?
    /// 连线 overlay 视图（由 CanvasNodeRenderer 创建后注册，用于绘制临时连线）
    weak var connectionOverlayView: ConnectionOverlayView?

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
    /// 画布平移/缩放后立即回调（用于连线层实时重渲染，不经过 SwiftUI 回路）
    var onViewportPanned: (() -> Void)?
    var onDeleteSelectedNodes: (() -> Void)?
    var onFocusSelectedNode: (() -> Void)?
    var onNodeJumpNumbersRequested: ((Bool) -> Void)? // true=显示, false=隐藏
    /// 选中节点变化时回调（选中 ID 集合, 第一个选中节点的屏幕 frame or nil）
    var onSelectionChanged: ((Set<UUID>, CGRect?) -> Void)?

    // MARK: - 连线工具状态
    /// 连线起点节点 ID（nil = 未开始连线）
    var connectingFromNodeId: UUID? = nil {
        didSet {
            needsDisplay = true
            syncTemporaryConnectionToOverlay()
        }
    }
    /// 连线时鼠标当前屏幕坐标（用于绘制临时连线）
    var connectionDragPoint: CGPoint? = nil {
        didSet {
            syncTemporaryConnectionToOverlay()
        }
    }
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
        // 如果尚未设置连线起点但有选中节点，自动将首个选中节点设为起点
        // （L 键入口已提前设置 connectingFromNodeId，此处不覆盖）
        if connectingFromNodeId == nil, let firstSelected = selectedNodeIds.first {
            connectingFromNodeId = firstSelected
        }
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

    /// 将临时连线状态同步到 ConnectionOverlayView（确保临时连线绘制在正确的视图层级）
    func syncTemporaryConnectionToOverlay() {
        guard let overlay = connectionOverlayView else { return }
        if let fromId = connectingFromNodeId,
           let fromCanvasFrame = nodeCanvasFrames[fromId] {
            let screenFrame = canvasRectToScreen(fromCanvasFrame)
            overlay.tempConnectionFromFrame = screenFrame
            overlay.tempConnectionToPoint = connectionDragPoint
        } else {
            overlay.tempConnectionFromFrame = nil
            overlay.tempConnectionToPoint = nil
        }
    }

    /// 节点内容类型查询（由 CanvasNodeRenderer 在创建节点后注册）
    var nodeContentTypes: [UUID: String] = [:]  // nodeId → "terminal"|"stickyNote"|"portal"|"fileTree"

    /// 节点 SwiftUI 容器（由 CanvasNodeRenderer 创建后注册，供 hitTestCanvas 使用）
    weak var nodesHostingView: CanvasNodesView?

    /// 当前画布节点列表（由 CanvasNodeRenderer.sync() 同步，供 hitTestCanvas 使用）
    /// 注意：赋值时自动触发排序缓存更新。高频帧内 frame 更新请使用 updateNodeFrameInPlace。
    var currentNodes: [CanvasNode] = [] {
        didSet {
            guard !_skipSortOnDidSet else { return }
            invalidateSortedNodesCache()
        }
    }
    /// 内部标志：为 true 时 currentNodes.didSet 跳过排序（仅 frame 变化时使用）
    private var _skipSortOnDidSet = false

    /// 按 zIndex 升序预排序的节点缓存（供 SwiftUI 渲染 + hitTest 使用，避免每帧 O(n log n)）
    private(set) var sortedNodesByZIndex: [CanvasNode] = []
    /// 按 zIndex 降序预排序的节点缓存（供 hitTest 从前到后命中检测使用）
    private(set) var sortedNodesByZIndexDesc: [CanvasNode] = []

    /// 视口裁剪缓存：避免 layout() 每帧重新遍历所有节点
    private var _cachedViewportNodes: [CanvasNode] = []
    private var _cachedViewportOrigin: CGPoint = .zero
    private var _cachedViewportZoom: CGFloat = 0
    private var _viewportCacheDirty: Bool = true
    /// 视口缓存容差：origin 变化小于此值（画布坐标）时不重新裁剪，避免微小平移触发 O(n) 遍历
    private static let viewportCacheTolerance: CGFloat = 50.0

    /// pan/zoom 时 rootView 节流：上次更新 rootView 的时间戳
    /// 连续 pan/zoom 期间最多 60fps（每 16ms 最多一次 rootView 更新），避免每帧重建 SwiftUI 树
    private var _lastRootViewUpdateTime: TimeInterval = 0
    private static let rootViewUpdateMinInterval: TimeInterval = 1.0 / 60.0  // 60fps 上限

    private func invalidateSortedNodesCache() {
        sortedNodesByZIndex = currentNodes.sorted { $0.zIndex < $1.zIndex }
        sortedNodesByZIndexDesc = sortedNodesByZIndex.reversed()
    }

    /// 仅更新指定节点的 frame（不触发全量 sort，因为 zIndex 未变）
    /// 用于拖动/resize 等高频场景，避免每帧 O(n log n) + O(n) 数组拷贝
    func updateNodeFrameInPlace(id: UUID, frame: CGRect) {
        _skipSortOnDidSet = true
        for i in currentNodes.indices where currentNodes[i].id == id {
            currentNodes[i].frame = frame
            break
        }
        _skipSortOnDidSet = false
        // 同步更新排序缓存中对应条目的 frame（zIndex 不变所以位置不变）
        for i in sortedNodesByZIndex.indices where sortedNodesByZIndex[i].id == id {
            sortedNodesByZIndex[i].frame = frame
            break
        }
        for i in sortedNodesByZIndexDesc.indices where sortedNodesByZIndexDesc[i].id == id {
            sortedNodesByZIndexDesc[i].frame = frame
            break
        }
    }

    /// 原地更新指定节点的 isLocked（不触发全量 sort，同步排序缓存 + 视口缓存）
    func updateNodeLockedInPlace(id: UUID, isLocked: Bool) {
        _skipSortOnDidSet = true
        for i in currentNodes.indices where currentNodes[i].id == id {
            currentNodes[i].isLocked = isLocked
            break
        }
        _skipSortOnDidSet = false
        for i in sortedNodesByZIndex.indices where sortedNodesByZIndex[i].id == id {
            sortedNodesByZIndex[i].isLocked = isLocked
            break
        }
        for i in sortedNodesByZIndexDesc.indices where sortedNodesByZIndexDesc[i].id == id {
            sortedNodesByZIndexDesc[i].isLocked = isLocked
            break
        }
        _viewportCacheDirty = true
    }

    /// 原地更新指定节点的 content（不触发全量 sort，同步排序缓存 + 视口缓存）
    func updateNodeContentInPlace(id: UUID, content: NodeContent) {
        _skipSortOnDidSet = true
        for i in currentNodes.indices where currentNodes[i].id == id {
            currentNodes[i].content = content
            break
        }
        _skipSortOnDidSet = false
        for i in sortedNodesByZIndex.indices where sortedNodesByZIndex[i].id == id {
            sortedNodesByZIndex[i].content = content
            break
        }
        for i in sortedNodesByZIndexDesc.indices where sortedNodesByZIndexDesc[i].id == id {
            sortedNodesByZIndexDesc[i].content = content
            break
        }
        _viewportCacheDirty = true
    }

    /// 批量更新多个节点的 frame（不触发全量 sort）
    func updateNodeFramesInPlace(frames: [UUID: CGRect]) {
        _skipSortOnDidSet = true
        for i in currentNodes.indices {
            if let newFrame = frames[currentNodes[i].id] {
                currentNodes[i].frame = newFrame
            }
        }
        _skipSortOnDidSet = false
        // 同步更新排序缓存
        for i in sortedNodesByZIndex.indices {
            if let newFrame = frames[sortedNodesByZIndex[i].id] {
                sortedNodesByZIndex[i].frame = newFrame
            }
        }
        for i in sortedNodesByZIndexDesc.indices {
            if let newFrame = frames[sortedNodesByZIndexDesc[i].id] {
                sortedNodesByZIndexDesc[i].frame = newFrame
            }
        }
    }

    /// 节点拖动中帧级回调（连线物理引擎用此更新端点）
    /// 参数：被拖动节点的 ID 集合
    var onNodeFramesDuringDrag: ((Set<UUID>) -> Void)?

    /// option+拖拽复制节点回调
    var onDuplicateNode: ((UUID) -> Void)?

    /// 右键菜单：关闭节点回调（由 CanvasNodeRenderer 设置）
    var onContextMenuClose: ((UUID) -> Void)?
    /// 右键菜单：重命名节点回调（由 CanvasNodeRenderer 设置）
    var onContextMenuRename: ((UUID) -> Void)?
    /// 右键菜单：锁定/解锁节点回调（由 CanvasNodeRenderer 设置）
    var onContextMenuLockToggle: ((UUID) -> Void)?
    /// 右键菜单：编辑终端（弹出 EditTerminalSheet）
    var onContextMenuEditTerminal: ((UUID) -> Void)?
    /// 右键菜单：开始连接
    var onContextMenuConnect: ((UUID) -> Void)?
    /// 右键菜单：分配角色（Terminal 专属）
    var onContextMenuAssignRole: ((UUID) -> Void)?
    /// 右键菜单：切换 Maestro 模式（Terminal 专属）
    var onContextMenuToggleMaestro: ((UUID) -> Void)?

    // MARK: - 画布空白区域右键菜单回调

    /// 右键菜单：在画布指定位置创建指定类型节点（nodeType, canvasPoint）
    /// nodeType: "terminal", "stickyNote", "portal", "fileTree", "text", "linkedFile"
    var onCanvasContextCreateNode: ((String, CGPoint) -> Void)?
    /// 右键菜单：在画布指定位置创建终端节点（presetIndex, canvasPoint）
    var onCanvasContextCreateTerminal: ((Int, CGPoint) -> Void)?
    /// 右键菜单：粘贴（画布坐标）
    var onCanvasContextPaste: ((CGPoint) -> Void)?
    /// Agent 预设列表（供画布右键菜单 Terminal 子菜单使用）
    var agentPresets: [AgentPreset] = []

    /// 节点 zIndex 变化回调（节点ID → 新 zIndex），由 WorkspaceManager 持久化
    var onNodeZIndexChanged: ((UUID, Int) -> Void)?

    // MARK: - 节点层级管理

    /// 将指定节点提升到最高层级（zIndex 最大值 + 1）
    func bringNodesToFront(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let maxZ = currentNodes.map { $0.zIndex }.max() ?? 0

        // 判断是否已经独占最高层：选中节点的 zIndex 都等于 maxZ，
        // 且没有其他未选中节点也在 maxZ（即选中节点已是唯一最高层）
        let otherNodesAtMax = currentNodes.contains { node in
            !ids.contains(node.id) && node.zIndex >= maxZ
        }
        let selectedAllAtMax = ids.allSatisfy { id in
            currentNodes.first { $0.id == id }?.zIndex == maxZ
        }
        if selectedAllAtMax && !otherNodesAtMax { return }

        let newZ = maxZ + 1
        var changed = false
        for i in currentNodes.indices {
            if ids.contains(currentNodes[i].id) {
                currentNodes[i].zIndex = newZ
                onNodeZIndexChanged?(currentNodes[i].id, newZ)
                changed = true
            }
        }
        // 层级变化后重建排序缓存（下标赋值不触发 didSet，必须手动刷新）
        if changed {
            invalidateSortedNodesCache()
            _viewportCacheDirty = true
            NotificationCenter.default.post(
                name: .canvasSelectionChanged,
                object: nil,
                userInfo: ["selectedIds": selectedNodeIds]
            )
        }
    }

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
        setupBackgroundView()
        setupDrawingLayerView()
        setupSnapGuideView()
    }

    private func setupBackgroundView() {
        let bg = CanvasBackground(frame: bounds)
        bg.autoresizingMask = [.width, .height]
        bg.canvasOrigin = canvasOrigin
        bg.zoom = zoom
        bg.backgroundMode = backgroundMode
        addSubview(bg)
        backgroundView = bg
    }

    private func setupDrawingLayerView() {
        let drawLayer = DrawingLayerView(frame: bounds)
        drawLayer.autoresizingMask = [.width, .height]
        drawLayer.canvasOrigin = canvasOrigin
        drawLayer.zoom = zoom
        addSubview(drawLayer)
        drawingLayerView = drawLayer
    }

    private func setupSnapGuideView() {
        let snapView = MagneticSnapGuideView(frame: bounds)
        snapView.autoresizingMask = [.width, .height]
        addSubview(snapView)
        snapGuideView = snapView
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

    // MARK: - 坐标系

    override var isFlipped: Bool { true }

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

        // 用 canvasFrame 做命中测试：不依赖 nodeViews（NSHostingView 迁移后为空）
        for selectedId in selectedNodeIds {
            guard let canvasFrame = nodeCanvasFrames[selectedId] else { continue }
            let screenFrame = canvasRectToScreen(canvasFrame)
            guard screenFrame.contains(locInCanvas) else { continue }
            // 排除 header 区域（header 在顶部，flipped 坐标系 minY = 顶边）
            let headerScreenHeight = CanvasNodeConstants.headerHeight * zoom
            let contentScreenFrame = CGRect(
                x: screenFrame.minX,
                y: screenFrame.minY + headerScreenHeight,
                width: screenFrame.width,
                height: screenFrame.height - headerScreenHeight
            )
            guard contentScreenFrame.contains(locInCanvas) else { break }
            // Terminal 节点：路由滚动事件给 TerminalView
            if let provider = TerminalManager.shared.providers[selectedId],
               let terminalView = provider.terminalView {
                terminalView.scrollWheel(with: event)
                return nil
            }
            // FileTree 节点：路由滚动事件给内部 NSScrollView
            if let fileTreeView = FileTreeViewRegistry.shared.view(for: selectedId),
               let scrollView = fileTreeView.innerScrollView {
                scrollView.scrollWheel(with: event)
                return nil
            }
            // Note 节点：路由滚动事件给 NSTextView 的 ScrollView
            if let noteScrollView = NoteScrollViewRegistry.shared.scrollView(for: selectedId) {
                noteScrollView.scrollWheel(with: event)
                return nil
            }
            // Portal 节点：路由滚动事件给 WKWebView
            if let webView = PortalWebViewStore.shared.webView(for: selectedId) {
                webView.scrollWheel(with: event)
                return nil
            }
            // 其他节点：交由画布处理
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

        // 更新 CanvasNodesView 的 frame 以填满画布视口
        nodesHostingView?.frame = bounds

        // 更新 SwiftUI 节点树的 canvasOrigin/zoom，触发节点重新定位
        if let hostingView = nodesHostingView {
            let current = hostingView.rootView

            // 拖动中跳过视口裁剪（不重新筛选可见集），但需把实时 frame 同步进缓存
            let isDragging: Bool
            switch interaction {
            case .draggingNode, .batchDragging, .resizingNode:
                isDragging = true
            default:
                isDragging = false
            }

            if isDragging {
                // 拖动中以 sortedNodesByZIndex 为权威来源重建 _cachedViewportNodes：
                // 1. 排序顺序跟随最新 zIndex（bringNodesToFront 已更新 sortedNodesByZIndex）
                // 2. frame 取实时值（updateNodeFrameInPlace 已同步到 sortedNodesByZIndex）
                let cachedIds = Set(_cachedViewportNodes.map { $0.id })
                _cachedViewportNodes = sortedNodesByZIndex.filter { cachedIds.contains($0.id) }
            } else {
                // 仅在视口参数大幅变化或缓存显式失效时重新裁剪（避免每帧 O(n) 遍历）
                // 容差策略：origin 微小变化（< 50 画布单位 ≈ 亚节点级平移）不触发重算
                let originDelta = hypot(_cachedViewportOrigin.x - canvasOrigin.x,
                                        _cachedViewportOrigin.y - canvasOrigin.y)
                let needsRecalc = _viewportCacheDirty
                    || _cachedViewportZoom != zoom
                    || currentNodes.count != _cachedViewportNodes.count
                    || originDelta > Self.viewportCacheTolerance
                if needsRecalc {
                    _cachedViewportNodes = viewportCulledNodes()
                    _cachedViewportOrigin = canvasOrigin
                    _cachedViewportZoom = zoom
                    _viewportCacheDirty = false
                }
            }

            // 仅当 origin/zoom/可见节点变化时才重建 rootView（避免完全无变化时的冗余赋值）
            let nodesChanged = current.nodes != _cachedViewportNodes
            let viewportChanged = current.canvasOrigin != canvasOrigin || current.zoom != zoom
            if nodesChanged || viewportChanged {
                // pan/zoom 时节流：60fps 上限，避免每帧重建 SwiftUI 树触发所有终端 updateNSView
                // 节点集合变化时强制立即更新（用户操作需要即时响应）
                let now = CACurrentMediaTime()
                let shouldUpdate = nodesChanged
                    || isDragging  // 节点拖拽时保持实时更新
                    || (now - _lastRootViewUpdateTime) >= Self.rootViewUpdateMinInterval
                guard shouldUpdate else { return }
                _lastRootViewUpdateTime = now

                hostingView.rootView = CanvasNodesSwiftUIView(
                    nodes: _cachedViewportNodes,
                    canvasOrigin: canvasOrigin,
                    zoom: zoom,
                    selectedNodeIds: current.selectedNodeIds,
                    lockedNodeIds: current.lockedNodeIds,
                    workspace: current.workspace,
                    dropTargetNodeId: current.dropTargetNodeId,
                    onActivated: current.onActivated,
                    onClose: current.onClose,
                    onRename: current.onRename,
                    onDuplicate: current.onDuplicate,
                    onLockToggle: current.onLockToggle
                )
            }
        }
    }

    // MARK: - 视口裁剪

    /// 视口裁剪边距（画布坐标单位），超出视口此距离以外的节点不渲染
    /// 使用较大边距确保节点进入视口前已经准备好，避免闪烁
    private static let viewportCullMargin: CGFloat = 200

    /// 计算当前视口可见的节点列表（按 zIndex 升序）
    /// 逻辑：将视口屏幕 bounds 转为画布坐标，加上边距后与节点 frame 做 intersects 判断
    func viewportCulledNodes() -> [CanvasNode] {
        let viewportCanvas = screenRectToCanvas(bounds).insetBy(
            dx: -Self.viewportCullMargin,
            dy: -Self.viewportCullMargin
        )
        return sortedNodesByZIndex.filter { node in
            viewportCanvas.intersects(node.frame)
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
        // 拖动/resize 期间不允许外部覆盖被交互节点的 frame
        switch interaction {
        case .draggingNode(let did, _, _) where did == id: return
        case .batchDragging(let frames, _, _) where frames.keys.contains(id): return
        case .resizingNode(let rid, _, _, _) where rid == id: return
        case .mayDragNode(let mid, _, _, _) where mid == id: return
        default: break
        }
        nodeCanvasFrames[id] = canvasFrame
        currentNodes = currentNodes.map { node in
            guard node.id == id else { return node }
            return CanvasNode(id: node.id, frame: canvasFrame, content: node.content,
                              zIndex: node.zIndex, isLocked: node.isLocked)
        }
        // 节点 frame 变化可能影响视口可见性，强制使裁剪缓存失效
        _viewportCacheDirty = true
        needsLayout = true
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
        let frame = selectedNodeIds.first
            .flatMap { nodeCanvasFrames[$0] }
            .map { canvasRectToScreen($0) }
        callback(selectedNodeIds, frame)
    }

    // MARK: - 统一交互状态机

    /// 当前画布交互状态（替换所有散落的拖动/选择/resize 状态变量）
    var interaction: CanvasInteraction = .idle

    /// 拖动期间用于 drag guideline 绘制
    var dragGuidelines: [GuideLine] = [] {
        didSet {
            snapGuideView?.guidelines = dragGuidelines
        }
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
    /// 绘制模式网格吸附：上一次吸附后的画布矩形（用于检测网格跨越并触发 haptic）
    var drawingLastSnappedRect: CGRect?
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

    // MARK: - 前景覆盖物绘制

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 背景由 CanvasBackground 子视图负责绘制
        // 磁吸辅助线、框选矩形、绘制预览矩形由 MagneticSnapGuideView（最顶层）负责绘制
        // 临时连线已迁移到 ConnectionOverlayView 绘制（避免被子视图遮挡）
    }

    // MARK: - Tracking Area 维护

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // 连线模式下需要 mouseMoved 事件来跟踪鼠标位置
        if isInConnectingMode || connectingFromNodeId != nil {
            for ta in trackingAreas { removeTrackingArea(ta) }
            addTrackingArea(makeTrackingArea())
        }
    }
}

// MARK: - Context Menu

extension CanvasViewportView {

    /// 右键菜单：在 AppKit 层处理，避免 SwiftUI allowsHitTesting(false) 阻断问题
    /// 根据节点类型动态构建菜单项（对标 Maestri 产品行为）：
    /// - Terminal: Duplicate → Edit Terminal → Assign Role / Enable Maestro → Connect → Delete
    /// - Note: Duplicate → Rename → Connect → Delete
    /// - Portal: Duplicate → Connect → Delete
    /// - FileTree: Duplicate → Lock → Delete（使用节点内部工具栏，菜单精简）
    /// - Text/Drawing: Duplicate → Lock → Delete
    override func menu(for event: NSEvent) -> NSMenu? {
        let loc = convert(event.locationInWindow, from: nil)
        let hit = hitTestCanvas(at: loc)

        let nodeId: UUID?
        switch hit {
        case .nodeHeader(let id), .nodeFooter(let id), .nodeContent(let id, _), .nodeResize(let id, _):
            nodeId = id
        case .canvas:
            nodeId = nil
        }

        guard let id = nodeId else {
            return buildCanvasBlankMenu(at: loc)
        }
        guard let node = currentNodes.first(where: { $0.id == id }) else { return super.menu(for: event) }

        let menu = NSMenu()

        switch node.content {
        case .terminal(let tc):
            menu.addItem(menuItem("canvas.context.duplicate".localized, action: #selector(contextMenuDuplicate(_:)), id: id))
            menu.addItem(menuItem("canvas.context.edit_terminal".localized, action: #selector(contextMenuEditTerminal(_:)), id: id))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(menuItem("canvas.context.assign_role".localized, action: #selector(contextMenuAssignRole(_:)), id: id))
            let maestroTitle = tc.isManager ? "menu.disable_maestro".localized : "menu.enable_maestro".localized
            menu.addItem(menuItem(maestroTitle, action: #selector(contextMenuToggleMaestro(_:)), id: id))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(menuItem("canvas.context.connect".localized, action: #selector(contextMenuConnect(_:)), id: id))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(destructiveItem("canvas.context.delete".localized, action: #selector(contextMenuClose(_:)), id: id))

        case .stickyNote:
            menu.addItem(menuItem("canvas.context.duplicate".localized, action: #selector(contextMenuDuplicate(_:)), id: id))
            menu.addItem(menuItem("canvas.context.rename".localized, action: #selector(contextMenuRename(_:)), id: id))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(menuItem("canvas.context.connect".localized, action: #selector(contextMenuConnect(_:)), id: id))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(destructiveItem("canvas.context.delete".localized, action: #selector(contextMenuClose(_:)), id: id))

        case .portal:
            menu.addItem(menuItem("canvas.context.duplicate".localized, action: #selector(contextMenuDuplicate(_:)), id: id))
            menu.addItem(menuItem("canvas.context.rename".localized, action: #selector(contextMenuRename(_:)), id: id))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(menuItem("canvas.context.connect".localized, action: #selector(contextMenuConnect(_:)), id: id))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(destructiveItem("canvas.context.delete".localized, action: #selector(contextMenuClose(_:)), id: id))

        case .fileTree:
            menu.addItem(menuItem("canvas.context.duplicate".localized, action: #selector(contextMenuDuplicate(_:)), id: id))
            menu.addItem(menuItem("canvas.context.rename".localized, action: #selector(contextMenuRename(_:)), id: id))
            let lockTitle = node.isLocked ? "menu.unlock".localized : "menu.lock".localized
            menu.addItem(menuItem(lockTitle, action: #selector(contextMenuLockToggle(_:)), id: id))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(destructiveItem("canvas.context.delete".localized, action: #selector(contextMenuClose(_:)), id: id))

        case .text, .drawing:
            menu.addItem(menuItem("canvas.context.duplicate".localized, action: #selector(contextMenuDuplicate(_:)), id: id))
            let lockTitle = node.isLocked ? "menu.unlock".localized : "menu.lock".localized
            menu.addItem(menuItem(lockTitle, action: #selector(contextMenuLockToggle(_:)), id: id))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(destructiveItem("canvas.context.delete".localized, action: #selector(contextMenuClose(_:)), id: id))
        }

        return menu
    }

    // MARK: - Canvas Blank Area Context Menu

    /// 构建画布空白区域右键菜单（添加 → 终端/便签/附件/文件树/门户/文本 + 粘贴）
    private func buildCanvasBlankMenu(at screenPoint: CGPoint) -> NSMenu {
        let canvasPoint = screenToCanvas(screenPoint)
        let menu = NSMenu()

        // 「添加」子菜单
        let addItem = NSMenuItem(title: "canvas.context.add".localized, action: nil, keyEquivalent: "")
        addItem.image = NSImage(systemSymbolName: "plus.square", accessibilityDescription: nil)
        let addSubmenu = NSMenu()

        // 终端子菜单（含 Agent 预设列表）
        let terminalItem = NSMenuItem(title: "canvas.context.add.terminal".localized, action: nil, keyEquivalent: "")
        terminalItem.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        let terminalSubmenu = NSMenu()

        for (index, preset) in agentPresets.enumerated() where preset.isActive {
            let presetItem = NSMenuItem(title: preset.name, action: #selector(contextMenuCreateTerminalPreset(_:)), keyEquivalent: "")
            presetItem.target = self
            presetItem.tag = index
            presetItem.representedObject = NSValue(point: NSPoint(x: canvasPoint.x, y: canvasPoint.y))
            if let iconName = presetIconName(for: preset) {
                presetItem.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            }
            terminalSubmenu.addItem(presetItem)
        }
        terminalItem.submenu = terminalSubmenu
        addSubmenu.addItem(terminalItem)

        // 便签
        let noteItem = NSMenuItem(title: "canvas.context.add.note".localized, action: #selector(contextMenuCreateNote(_:)), keyEquivalent: "")
        noteItem.target = self
        noteItem.image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: nil)
        noteItem.representedObject = NSValue(point: NSPoint(x: canvasPoint.x, y: canvasPoint.y))
        addSubmenu.addItem(noteItem)

        // 附件（LinkedFile）
        let attachmentItem = NSMenuItem(title: "canvas.context.add.attachment".localized, action: #selector(contextMenuCreateAttachment(_:)), keyEquivalent: "")
        attachmentItem.target = self
        attachmentItem.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil)
        attachmentItem.representedObject = NSValue(point: NSPoint(x: canvasPoint.x, y: canvasPoint.y))
        addSubmenu.addItem(attachmentItem)

        // 文件树
        let fileTreeItem = NSMenuItem(title: "canvas.context.add.filetree".localized, action: #selector(contextMenuCreateFileTree(_:)), keyEquivalent: "")
        fileTreeItem.target = self
        fileTreeItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        fileTreeItem.representedObject = NSValue(point: NSPoint(x: canvasPoint.x, y: canvasPoint.y))
        addSubmenu.addItem(fileTreeItem)

        // 门户
        let portalItem = NSMenuItem(title: "canvas.context.add.portal".localized, action: #selector(contextMenuCreatePortal(_:)), keyEquivalent: "")
        portalItem.target = self
        portalItem.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        portalItem.representedObject = NSValue(point: NSPoint(x: canvasPoint.x, y: canvasPoint.y))
        addSubmenu.addItem(portalItem)

        // 文本
        let textItem = NSMenuItem(title: "canvas.context.add.text".localized, action: #selector(contextMenuCreateText(_:)), keyEquivalent: "")
        textItem.target = self
        textItem.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
        textItem.representedObject = NSValue(point: NSPoint(x: canvasPoint.x, y: canvasPoint.y))
        addSubmenu.addItem(textItem)

        addItem.submenu = addSubmenu
        menu.addItem(addItem)

        // 粘贴
        let pasteItem = NSMenuItem(title: "canvas.context.paste".localized, action: #selector(contextMenuPaste(_:)), keyEquivalent: "")
        pasteItem.target = self
        pasteItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        pasteItem.representedObject = NSValue(point: NSPoint(x: canvasPoint.x, y: canvasPoint.y))
        // 仅在剪贴板有内容时可用
        pasteItem.isEnabled = NSPasteboard.general.string(forType: .string) != nil
        menu.addItem(pasteItem)

        return menu
    }

    /// 根据 AgentPreset 获取 SF Symbol 图标名
    private func presetIconName(for preset: AgentPreset) -> String? {
        switch preset.agentType {
        case "claude_code": return "seal"
        case "codex": return "brain"
        case "gemini_cli": return "sparkle"
        case "open_code": return "rectangle.portrait"
        case "generic_shell": return "terminal"
        default: return preset.icon.isEmpty ? nil : preset.icon
        }
    }

    // MARK: - Canvas Blank Area Context Menu Actions

    @objc private func contextMenuCreateTerminalPreset(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        let canvasPoint = CGPoint(x: point.x, y: point.y)
        onCanvasContextCreateTerminal?(sender.tag, canvasPoint)
    }

    @objc private func contextMenuCreateNote(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        let canvasPoint = CGPoint(x: point.x, y: point.y)
        onCanvasContextCreateNode?("stickyNote", canvasPoint)
    }

    @objc private func contextMenuCreateAttachment(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        let canvasPoint = CGPoint(x: point.x, y: point.y)
        onCanvasContextCreateNode?("linkedFile", canvasPoint)
    }

    @objc private func contextMenuCreateFileTree(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        let canvasPoint = CGPoint(x: point.x, y: point.y)
        onCanvasContextCreateNode?("fileTree", canvasPoint)
    }

    @objc private func contextMenuCreatePortal(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        let canvasPoint = CGPoint(x: point.x, y: point.y)
        onCanvasContextCreateNode?("portal", canvasPoint)
    }

    @objc private func contextMenuCreateText(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        let canvasPoint = CGPoint(x: point.x, y: point.y)
        onCanvasContextCreateNode?("text", canvasPoint)
    }

    @objc private func contextMenuPaste(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        let canvasPoint = CGPoint(x: point.x, y: point.y)
        onCanvasContextPaste?(canvasPoint)
    }

    // MARK: - Menu Item Helpers

    private func menuItem(_ title: String, action: Selector, id: UUID) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.representedObject = id
        item.target = self
        return item
    }

    private func destructiveItem(_ title: String, action: Selector, id: UUID) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.representedObject = id
        item.target = self
        // 危险操作红色标记（macOS 标准做法：设置 attributedTitle）
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: NSColor.systemRed]
        )
        return item
    }

    // MARK: - Context Menu Actions

    @objc private func contextMenuRename(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuRename?(id)
    }

    @objc private func contextMenuDuplicate(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onDuplicateNode?(id)
    }

    @objc private func contextMenuLockToggle(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuLockToggle?(id)
    }

    @objc private func contextMenuClose(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuClose?(id)
    }

    @objc private func contextMenuEditTerminal(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuEditTerminal?(id)
    }

    @objc private func contextMenuConnect(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuConnect?(id)
    }

    @objc private func contextMenuAssignRole(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuAssignRole?(id)
    }

    @objc private func contextMenuToggleMaestro(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuToggleMaestro?(id)
    }
}

// MARK: - Comparable clamped

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
