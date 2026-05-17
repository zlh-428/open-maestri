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
    private var connectionDragPoint: CGPoint? = nil
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
        // 进入等待第一次点击的状态
        connectionDragPoint = nil
        needsDisplay = true
        // 安装鼠标追踪区域
        for ta in trackingAreas { removeTrackingArea(ta) }
        addTrackingArea(makeTrackingArea())
        // 光标切换为十字
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
        // 启用 layer-backed drawing 以提升滚动/缩放流畅度
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        canDrawConcurrently = true
        // 确保接收触摸板手势（pinch-to-zoom 需要 .indirect）
        allowedTouchTypes = [.indirect, .direct]
        // 注册 Finder 文件拖入支持
        registerDragTypes()
        // 监听 Minimap 平滑跳转通知
        NotificationCenter.default.addObserver(
            forName: .canvasJumpToOrigin,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self, let target = notif.userInfo?["origin"] as? CGPoint else { return }
            self.animateOriginTo(target)
        }
        // 监听工具栏/按钮缩放通知（以视口中心为锚点）
        NotificationCenter.default.addObserver(
            forName: .canvasZoomIn, object: nil, queue: .main
        ) { [weak self] _ in self?.zoomCanvas(delta: +0.25) }
        NotificationCenter.default.addObserver(
            forName: .canvasZoomOut, object: nil, queue: .main
        ) { [weak self] _ in self?.zoomCanvas(delta: -0.25) }
        NotificationCenter.default.addObserver(
            forName: .canvasZoomReset, object: nil, queue: .main
        ) { [weak self] _ in self?.zoomCanvas(toAbsolute: 1.0) }
        NotificationCenter.default.addObserver(
            forName: .toggleCanvasZoom, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let target: CGFloat = abs(zoom - 1.0) < 0.05 ? 0.5 : 1.0
            self.zoomCanvas(toAbsolute: target)
        }
    }

    /// 平滑动画跳转到指定画布原点（供 Minimap 点击等外部调用）
    func animateOriginTo(_ target: CGPoint, duration: TimeInterval = 0.3) {
        animateOrigin(from: canvasOrigin, to: target, startTime: CACurrentMediaTime(), duration: duration)
    }

    // MARK: - 第一响应者

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        print("[Canvas] becomeFirstResponder called, callStack:")
        Thread.callStackSymbols.prefix(8).forEach { print("  \($0)") }
        return true
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

    private func installScrollEventMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self else { return event }
            return self.routeScrollEvent(event)
        }
        // 调试：监控所有键盘事件，确认 keyDown 到达哪个视图
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            print("[KeyMonitor] keyDown: keyCode=\(event.keyCode) chars=\(event.characters ?? "") firstResponder=\(type(of: NSApp.keyWindow?.firstResponder)) isKeyWindow=\(NSApp.keyWindow?.isKeyWindow ?? false)")
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyUp]) { event in
            if event.type == .keyUp {
                print("[KeyMonitor] keyUp: keyCode=\(event.keyCode) isKeyWindow=\(NSApp.keyWindow?.isKeyWindow ?? false)")
            }
            return event
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
            // 若鼠标在已选中节点上，事件穿透给节点内容（终端滚动、WebView 滚动等）
            let hoveredNodeId = nodeIdForHitView(hitView)
            let isOverSelectedNode = hoveredNodeId.map { selectedNodeIds.contains($0) } ?? false
            if isOverSelectedNode {
                return event
            }

            // 未选中节点区域或空白区域：由画布统一处理（平移/缩放）
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

    /// 从 hitTest 返回的视图反查所属节点 ID
    private func nodeIdForHitView(_ hitView: NSView?) -> UUID? {
        guard let hitView else { return nil }
        for (id, view) in nodeViews {
            if hitView === view || hitView.isDescendant(of: view) {
                return id
            }
        }
        return nil
    }


    deinit {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
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
        for (id, view) in nodeViews {
            if id == draggingNodeId { continue }
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
        addSubview(view)
        updateNodeFrame(id: id, canvasFrame: canvasFrame)
    }

    func removeNodeView(id: UUID) {
        nodeViews[id]?.removeFromSuperview()
        nodeViews.removeValue(forKey: id)
        nodeCanvasFrames.removeValue(forKey: id)
    }

    func updateNodeFrame(id: UUID, canvasFrame: CGRect) {
        guard let view = nodeViews[id] else { return }
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
        print("[Selection] updateSelectionVisuals, selected=\(selectedNodeIds), currentFirstResponder=\(type(of: window?.firstResponder)) \(String(describing: window?.firstResponder))")
        for (id, view) in nodeViews {
            let selected = selectedNodeIds.contains(id)
            if let tv = view as? TerminalNodeView {
                tv.isSelected = selected
            }
            if let baseNode = view as? BaseNodeView {
                baseNode.isNodeSelected = selected
                // 单选时将键盘焦点转给节点内容（终端需要成为 firstResponder 才能接收输入）
                if selected && selectedNodeIds.count == 1 {
                    print("[Selection] calling onFocusRequested for node \(id)")
                    baseNode.onFocusRequested?()
                    print("[Selection] after onFocusRequested, firstResponder=\(type(of: window?.firstResponder)) \(String(describing: window?.firstResponder))")
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

    // MARK: - 键盘事件

    override func keyDown(with event: NSEvent) {
        print("[Canvas] keyDown intercepted: keyCode=\(event.keyCode) chars=\(event.characters ?? "") firstResponder=\(type(of: window?.firstResponder))")
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""

        // ⌘W - 删除选中节点
        if flags == .command && key == "w" {
            onDeleteSelectedNodes?()
            return
        }

        // \ - 聚焦/居中选中节点到视口
        if key == "\\" && flags.isEmpty {
            focusSelectedNodeInViewport()
            return
        }

        // ⌘P - 过滤/搜索
        if flags == .command && key == "p" {
            NotificationCenter.default.post(name: .showCanvasFilter, object: nil)
            return
        }

        // L - 启动连线工具（官方快捷键，非 ⌘L）
        if key == "l" && flags.isEmpty {
            if let firstSelected = selectedNodeIds.first {
                connectingFromNodeId = firstSelected
                isInConnectingMode = true
            }
            return
        }

        // H - 切换平移模式（Pan）
        if key == "h" && flags.isEmpty {
            togglePanMode()
            return
        }

        // ⌃Tab - 切换到下一个终端节点
        if event.keyCode == 48 /* Tab */ && flags == .control {
            cycleTerminalFocus(forward: true)
            return
        }

        // ⌃⇧Tab - 切换到上一个终端节点
        if event.keyCode == 48 /* Tab */ && flags == [.control, .shift] {
            cycleTerminalFocus(forward: false)
            return
        }

        // ⌘⇧B - 切换当前选中终端节点的滚动锁定
        if flags == [.command, .shift] && key == "b" {
            toggleAutoScrollLock()
            return
        }

        // Space - 进入平移模式
        if event.keyCode == 49 && !isSpaceHeld {
            isSpaceHeld = true
            NSCursor.openHand.set()
            return
        }

        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        // Space 释放 - 退出平移模式
        if event.keyCode == 49 {
            isSpaceHeld = false
            spaceDragStartOrigin = nil
            spaceDragStartMouse = nil
            NSCursor.arrow.set()
        }
        super.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmdHeld = flags.contains(.command)
        onNodeJumpNumbersRequested?(cmdHeld)
        assignJumpNumbers(visible: cmdHeld)

        // Space 键检测（用于 Space+拖拽平移）
        // NSEvent.ModifierFlags 不包含 Space，通过 keyDown/keyUp 跟踪
        super.flagsChanged(with: event)
    }

    /// ⌘ 按住时为所有 Terminal 节点分配跳转数字（1~9），松开时清除
    private func assignJumpNumbers(visible: Bool) {
        let terminalViews = nodeViews.values
            .compactMap { $0 as? TerminalNodeView }
            .sorted { $0.frame.minX < $1.frame.minX || ($0.frame.minX == $1.frame.minX && $0.frame.minY < $1.frame.minY) }
        for (i, tv) in terminalViews.enumerated() {
            tv.jumpNumber = visible ? (i < 9 ? i + 1 : nil) : nil
        }
    }

    // MARK: - ⌘+数字 终端跳转

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ⌘= / ⌘+ — 放大（以视口中心为锚点）
        if flags == .command,
           let key = event.charactersIgnoringModifiers,
           key == "=" || key == "+" {
            zoomCanvas(delta: +0.25)
            return true
        }

        // ⌘- — 缩小
        if flags == .command,
           let key = event.charactersIgnoringModifiers,
           key == "-" {
            zoomCanvas(delta: -0.25)
            return true
        }

        // ⌘0 — 重置缩放到 100%
        if flags == .command,
           let key = event.charactersIgnoringModifiers,
           key == "0" {
            zoomCanvas(toAbsolute: 1.0)
            return true
        }

        // ⌘1…9 — 终端跳转
        if flags == .command, let key = event.charactersIgnoringModifiers,
           let num = Int(key), num >= 1 && num <= 9 {
            jumpToTerminal(number: num)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - 键盘缩放辅助

    /// 以视口中心为锚点，按增量调整缩放
    private func zoomCanvas(delta: CGFloat) {
        let newZoom = (zoom + delta).clamped(to: Constants.canvasMinZoom...Constants.canvasMaxZoom)
        guard newZoom != zoom else { return }
        let viewCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        let canvasCenter = screenToCanvas(viewCenter)
        zoom = newZoom
        canvasOrigin = CGPoint(
            x: canvasCenter.x - viewCenter.x / zoom,
            y: canvasCenter.y - viewCenter.y / zoom
        )
        needsLayout = true
        needsDisplay = true
        notifyViewportChanged()
    }

    /// 以视口中心为锚点，设置绝对缩放值（如重置 100%）
    private func zoomCanvas(toAbsolute target: CGFloat) {
        let newZoom = target.clamped(to: Constants.canvasMinZoom...Constants.canvasMaxZoom)
        guard newZoom != zoom else { return }
        let viewCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        let canvasCenter = screenToCanvas(viewCenter)
        zoom = newZoom
        canvasOrigin = CGPoint(
            x: canvasCenter.x - viewCenter.x / zoom,
            y: canvasCenter.y - viewCenter.y / zoom
        )
        needsLayout = true
        needsDisplay = true
        notifyViewportChanged()
    }

    private func jumpToTerminal(number: Int) {
        // 找第 number 个 Terminal 节点视图
        let terminalViews = nodeViews.values.compactMap { $0 as? TerminalNodeView }
        let sorted = terminalViews.enumerated().sorted { $0.element.frame.minX < $1.element.frame.minX }
        guard number - 1 < sorted.count else { return }
        let target = sorted[number - 1].element
        window?.makeFirstResponder(target)
        // 平滑滚动视口使目标居中
        scrollToViewAnimated(target)
    }

    // MARK: - ⌃Tab 终端循环切换

    /// 按画布横坐标排序，循环切换到下一个/上一个终端节点
    private func cycleTerminalFocus(forward: Bool) {
        let sorted = sortedTerminalViews()
        guard !sorted.isEmpty else { return }

        // 找当前聚焦的终端索引
        let currentIndex: Int
        if let firstId = selectedNodeIds.first,
           let idx = sorted.firstIndex(where: { nodeId(forView: $0) == firstId }) {
            currentIndex = idx
        } else {
            currentIndex = forward ? sorted.count - 1 : 0
        }

        let nextIndex: Int
        if forward {
            nextIndex = (currentIndex + 1) % sorted.count
        } else {
            nextIndex = (currentIndex - 1 + sorted.count) % sorted.count
        }

        let target = sorted[nextIndex]
        if let targetId = nodeId(forView: target) {
            selectedNodeIds = [targetId]
        }
        window?.makeFirstResponder(target)
        scrollToViewAnimated(target)
    }

    /// 按画布 x 坐标排序的终端节点视图列表
    private func sortedTerminalViews() -> [TerminalNodeView] {
        nodeViews.values
            .compactMap { $0 as? TerminalNodeView }
            .sorted { $0.frame.minX < $1.frame.minX || ($0.frame.minX == $1.frame.minX && $0.frame.minY < $1.frame.minY) }
    }

    /// 反查节点视图对应的 UUID
    private func nodeId(forView view: NSView) -> UUID? {
        nodeViews.first(where: { $0.value === view })?.key
    }

    // MARK: - ⌘⇧B 滚动锁定

    /// 切换当前选中终端节点的自动滚动锁定状态
    private func toggleAutoScrollLock() {
        let targets = selectedNodeIds.isEmpty
            ? nodeViews.values.compactMap { $0 as? TerminalNodeView }
            : selectedNodeIds.compactMap { nodeViews[$0] as? TerminalNodeView }

        for tv in targets {
            tv.autoScrollLocked.toggle()
            // 通知对应 SwiftTermProvider 更新滚动行为
            if let nodeId = nodeId(forView: tv),
               let provider = TerminalProviderRegistry.shared.provider(for: nodeId) {
                provider.setAutoScrollLocked(tv.autoScrollLocked)
            }
        }
    }

    // MARK: - 聚焦到视口

    private func focusSelectedNodeInViewport() {
        guard let firstId = selectedNodeIds.first,
              let view = nodeViews[firstId] else { return }
        scrollToViewAnimated(view)
        onFocusSelectedNode?()
    }

    /// 立即（无动画）跳转到指定视图（内部同步使用）
    private func scrollToView(_ view: NSView) {
        let screenCenter = CGPoint(x: view.frame.midX, y: view.frame.midY)
        let canvasCenter = screenToCanvas(screenCenter)
        let newOriginX = canvasCenter.x - (bounds.width / 2) / zoom
        let newOriginY = canvasCenter.y - (bounds.height / 2) / zoom
        canvasOrigin = CGPoint(x: newOriginX, y: newOriginY)
        notifyViewportChanged()
    }

    /// 平滑动画跳转到指定视图（NSAnimationContext，duration=0.35s easeInOut）
    func scrollToViewAnimated(_ view: NSView, duration: TimeInterval = 0.35) {
        let screenCenter = CGPoint(x: view.frame.midX, y: view.frame.midY)
        let canvasCenter = screenToCanvas(screenCenter)
        let targetOriginX = canvasCenter.x - (bounds.width / 2) / zoom
        let targetOriginY = canvasCenter.y - (bounds.height / 2) / zoom
        let targetOrigin = CGPoint(x: targetOriginX, y: targetOriginY)

        let startOrigin = canvasOrigin
        let startTime = CACurrentMediaTime()

        // 使用 DisplayLink 级别的定时器实现平滑动画
        // NSAnimationContext 不直接驱动自定义属性，这里用 CVDisplayLink 等效方案：
        // 通过 DispatchSource 每帧更新 canvasOrigin
        animateOrigin(from: startOrigin, to: targetOrigin, startTime: startTime, duration: duration)
    }

    /// 逐帧插值 canvasOrigin（easeInOut 缓动）
    private func animateOrigin(from: CGPoint, to: CGPoint, startTime: CFTimeInterval, duration: TimeInterval) {
        // 取消正在进行的动画
        animationTimer?.invalidate()
        animationTimer = nil

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(elapsed / duration, 1.0)
            let eased = Self.easeInOut(progress)

            let newX = from.x + (to.x - from.x) * eased
            let newY = from.y + (to.y - from.y) * eased
            self.canvasOrigin = CGPoint(x: newX, y: newY)
            self.notifyViewportChanged()

            if progress >= 1.0 {
                t.invalidate()
                self.animationTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    /// easeInOut 缓动函数
    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
    }

    /// 当前活跃的滚动动画计时器
    private var animationTimer: Timer?

    // MARK: - 平移模式

    private var isPanMode = false
    /// Space 键按住时进入平移模式
    private var isSpaceHeld = false
    /// Space+拖拽平移的状态
    private var spaceDragStartOrigin: CGPoint?
    private var spaceDragStartMouse: CGPoint?

    private func togglePanMode() {
        isPanMode = !isPanMode
        NSCursor.closedHand.set()
    }

    // MARK: - 节点拖动（画布层统一处理，避免 layout() 干扰）

    /// 正在被拖动的节点 ID（nil = 未拖动）
    private var draggingNodeId: UUID? = nil
    /// 拖动开始时鼠标在 canvas 坐标系中的位置
    private var dragStartCanvasMouse: CGPoint? = nil
    /// 拖动开始时节点的画布 frame
    private var dragStartCanvasFrame: CGRect? = nil
    /// 上次触发磁力吸附的状态（用于检测从无→有触发 haptic）
    private var lastSnapActive: Bool = false
    /// 上次网格吸附后的坐标（用于检测是否跨格，nil = 拖动尚未开始）
    private var lastSnappedGridOrigin: CGPoint? = nil
    /// 当前拖动中的参考线（用于绘制）
    private(set) var dragGuidelines: [GuideLine] = [] {
        didSet { needsDisplay = true }
    }

    /// 节点拖动回调（拖动完成时，通知 renderer 持久化）
    var onNodeDragEnded: ((UUID, CGRect) -> Void)?

    /// 由 BaseNodeView.mouseDown 调用，初始化画布层节点拖动
    func beginNodeDrag(nodeId: UUID?, screenLoc: CGPoint) {
        guard let nodeId else { return }
        draggingNodeId = nodeId
        dragStartCanvasMouse = screenToCanvas(screenLoc)
        dragStartCanvasFrame = nodeCanvasFrames[nodeId]
        lastSnapActive = false
        lastSnappedGridOrigin = nil
    }

    // MARK: - 鼠标点击（选择节点）

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let hit = hitTest(loc)

        // Space+点击 进入平移拖拽
        if isSpaceHeld {
            spaceDragStartOrigin = canvasOrigin
            spaceDragStartMouse = loc
            NSCursor.closedHand.set()
            return
        }

        // 连线模式（isInConnectingMode）：点击节点建立连接，点击空白取消
        if isInConnectingMode {
            if let nodeId = nodeId(for: hit) {
                handleConnectionClick(nodeId: nodeId)
            } else {
                // 点击空白取消连线
                deactivateConnectionMode()
            }
            return
        }

        // 有起点时的遗留处理（兼容程序触发的连线）
        if connectingFromNodeId != nil {
            if let nodeId = nodeId(for: hit) {
                handleConnectionClick(nodeId: nodeId)
                return
            } else {
                connectingFromNodeId = nil
                connectionDragPoint = nil
                needsDisplay = true
                return
            }
        }

        // 节点绘制模式：在空白处（非节点区域）点击/拖拽创建节点
        if isInDrawingMode && nodeId(for: hit) == nil {
            drawingStartPoint = loc
            return
        }

        // 节点选中由 BaseNodeView.onNodeClicked 回调处理；
        // canvas mouseDown 只负责点击空白区域的清除选中
        if nodeId(for: hit) == nil {
            if !event.modifierFlags.contains(.command) {
                selectedNodeIds.removeAll()
            }
            window?.makeFirstResponder(self)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if connectingFromNodeId != nil {
            connectionDragPoint = convert(event.locationInWindow, from: nil)
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        // Space+拖拽平移
        if isSpaceHeld, let startOrigin = spaceDragStartOrigin, let startMouse = spaceDragStartMouse {
            let dx = (loc.x - startMouse.x) / zoom
            let dy = (loc.y - startMouse.y) / zoom
            canvasOrigin = CGPoint(x: startOrigin.x - dx, y: startOrigin.y - dy)
            needsLayout = true
            notifyViewportChanged()
            return
        }

        // 节点绘制模式拖拽
        if isInDrawingMode, drawingStartPoint != nil {
            drawingCurrentPoint = loc
            needsDisplay = true
            return
        }

        if connectingFromNodeId != nil {
            connectionDragPoint = loc
            needsDisplay = true
            return
        }

        // 节点拖动（画布层统一处理）
        if let nodeId = draggingNodeId,
           let startMouse = dragStartCanvasMouse,
           let startFrame = dragStartCanvasFrame,
           let view = nodeViews[nodeId] {

            let currentCanvas = screenToCanvas(loc)
            let rawDX = currentCanvas.x - startMouse.x
            let rawDY = currentCanvas.y - startMouse.y
            var newOrigin = CGPoint(
                x: startFrame.origin.x + rawDX,
                y: startFrame.origin.y + rawDY
            )
            var newFrame = CGRect(origin: newOrigin, size: startFrame.size)

            if event.modifierFlags.contains(.command) {
                // ⌘+拖拽：磁力瓦片对齐（吸附到相邻节点边缘）
                let otherFrames = nodeCanvasFrames
                    .filter { $0.key != nodeId }
                    .map { $0.value }
                let (snapped, guidelines) = TileSnapping.snap(
                    draggingFrame: newFrame,
                    against: otherFrames
                )
                let snapActive = snapped != newOrigin
                newOrigin = snapped
                newFrame = CGRect(origin: newOrigin, size: startFrame.size)
                dragGuidelines = guidelines
                if snapActive && !lastSnapActive {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                lastSnapActive = snapActive
            } else {
                // 普通拖拽：先尝试吸附到相邻节点边缘，无相邻节点则回落到 16px 网格
                let otherFrames = nodeCanvasFrames
                    .filter { $0.key != nodeId }
                    .map { $0.value }
                let (nodeSnapped, guidelines) = TileSnapping.snap(
                    draggingFrame: newFrame,
                    against: otherFrames
                )
                let nodeSnapActive = nodeSnapped != newOrigin
                if nodeSnapActive {
                    newOrigin = nodeSnapped
                    dragGuidelines = guidelines
                    if !lastSnapActive {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                    lastSnapActive = true
                } else {
                    dragGuidelines = []
                    let gridSnapped = snapToGrid(newOrigin, size: startFrame.size)
                    let gridChanged = gridSnapped != lastSnappedGridOrigin
                    newOrigin = gridSnapped
                    if gridChanged && lastSnappedGridOrigin != nil {
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    }
                    lastSnappedGridOrigin = gridSnapped
                    lastSnapActive = false
                }
                newFrame = CGRect(origin: newOrigin, size: startFrame.size)
            }

            // 直接更新屏幕 frame 和画布坐标缓存（禁用隐式动画，不触发 layout()）
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.frame = canvasRectToScreen(newFrame)
            view.setBoundsSize(newFrame.size)
            CATransaction.commit()
            nodeCanvasFrames[nodeId] = newFrame
        }
    }

    /// 将节点 frame 的四条边吸附到背景网格线（与 drawLineGrid 使用的坐标系一致）
    /// 分别对 left/right/top/bottom 四边取整，选择位移量最小的那条边对齐
    private func snapToGrid(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let grid: CGFloat = 16

        let left   = origin.x
        let right  = origin.x + size.width
        let bottom = origin.y
        let top    = origin.y + size.height

        let snappedLeft   = (left   / grid).rounded() * grid
        let snappedRight  = (right  / grid).rounded() * grid
        let snappedBottom = (bottom / grid).rounded() * grid
        let snappedTop    = (top    / grid).rounded() * grid

        let dx = abs(snappedLeft - left) <= abs(snappedRight - right)
            ? snappedLeft - left
            : snappedRight - right
        let dy = abs(snappedBottom - bottom) <= abs(snappedTop - top)
            ? snappedBottom - bottom
            : snappedTop - top

        return CGPoint(x: origin.x + dx, y: origin.y + dy)
    }

    override func mouseUp(with event: NSEvent) {
        // Space+拖拽结束
        if isSpaceHeld {
            spaceDragStartOrigin = nil
            spaceDragStartMouse = nil
            NSCursor.openHand.set()
        }

        // 节点拖动结束：持久化最终 canvas frame
        if let nodeId = draggingNodeId, let finalFrame = nodeCanvasFrames[nodeId] {
            dragGuidelines = []
            onNodeDragEnded?(nodeId, finalFrame)
        }
        draggingNodeId = nil
        dragStartCanvasMouse = nil
        dragStartCanvasFrame = nil
        lastSnapActive = false
        lastSnappedGridOrigin = nil

        // 节点绘制模式完成
        if isInDrawingMode, let start = drawingStartPoint {
            let current = drawingCurrentPoint ?? start
            let rect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )

            if rect.width > 20 && rect.height > 20 {
                // 拖拽绘制：使用用户绘制的尺寸
                let canvasRect = CGRect(
                    origin: screenToCanvas(rect.origin),
                    size: CGSize(width: rect.width / zoom, height: rect.height / zoom)
                )
                onNodeDrawn?(drawingNodeType, canvasRect)
            } else {
                // 点击创建：使用默认尺寸，以点击位置为中心
                let defaultSize = defaultNodeSize(for: drawingNodeType)
                let canvasPoint = screenToCanvas(start)
                let canvasRect = CGRect(
                    x: canvasPoint.x - defaultSize.width / 2,
                    y: canvasPoint.y - defaultSize.height / 2,
                    width: defaultSize.width,
                    height: defaultSize.height
                )
                onNodeDrawn?(drawingNodeType, canvasRect)
            }

            drawingStartPoint = nil
            drawingCurrentPoint = nil
            needsDisplay = true
            return
        }
    }

    // MARK: - 节点绘制模式

    /// 是否处于节点绘制模式（工具栏选中工具后激活）
    var isInDrawingMode: Bool = false
    /// 当前绘制的节点类型
    var drawingNodeType: String = "terminal"
    /// 绘制起始点（屏幕坐标）
    private var drawingStartPoint: CGPoint?
    /// 绘制当前点（屏幕坐标）
    private var drawingCurrentPoint: CGPoint?
    /// 绘制完成回调（传入节点类型和画布坐标 CGRect）
    var onNodeDrawn: ((String, CGRect) -> Void)?

    /// 点击创建时的默认节点尺寸（画布坐标）
    private func defaultNodeSize(for nodeType: String) -> CGSize {
        switch nodeType {
        case "terminal":
            return CGSize(width: 600, height: 400)
        case "stickyNote":
            return CGSize(width: 300, height: 240)
        case "portal":
            return CGSize(width: 500, height: 380)
        case "fileTree":
            return CGSize(width: 360, height: 480)
        default:
            return CGSize(width: 400, height: 300)
        }
    }

    // MARK: - 连线辅助

    private func nodeId(for view: NSView?) -> UUID? {
        guard let v = view else { return nil }
        for (id, nodeView) in nodeViews {
            if nodeView === v || v.isDescendant(of: nodeView) { return id }
        }
        return nil
    }

    private func handleConnectionClick(nodeId: UUID) {
        if let fromId = connectingFromNodeId {
            // 第二次点击：完成连线
            if fromId != nodeId {
                onConnectionCreated?(fromId, nodeId)
            }
            connectingFromNodeId = nil
            connectionDragPoint = nil
            // 连线完成后退出连线模式（通知 SwiftUI 层更新 isConnecting）
            isInConnectingMode = false
        } else {
            // 第一次点击：设置起点，选中节点
            connectingFromNodeId = nodeId
            selectedNodeIds = [nodeId]
            // 开启鼠标跟踪
            for ta in trackingAreas { removeTrackingArea(ta) }
            addTrackingArea(makeTrackingArea())
        }
        needsDisplay = true
    }

    private func makeTrackingArea() -> NSTrackingArea {
        NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved],
            owner: self,
            userInfo: nil
        )
    }

    // MARK: - 手势（触控板平移和缩放）

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            // ⌘+滚轮 缩放（以鼠标位置为锚点）
            let delta = event.scrollingDeltaY * 0.01
            let newZoom = (zoom + delta).clamped(to: Constants.canvasMinZoom...Constants.canvasMaxZoom)
            let mouseScreen = convert(event.locationInWindow, from: nil)
            let mouseCanvas = screenToCanvas(mouseScreen)
            zoom = newZoom
            canvasOrigin = CGPoint(
                x: mouseCanvas.x - mouseScreen.x / zoom,
                y: mouseCanvas.y - mouseScreen.y / zoom
            )
        } else {
            // 触摸板两指平移：手指方向 = 画布移动方向（自然滚动）
            // scrollingDeltaX/Y 已考虑自然滚动设置
            // 在本坐标系中 origin 增大 = 向右/向下看，所以用减号
            canvasOrigin = CGPoint(
                x: canvasOrigin.x - event.scrollingDeltaX / zoom,
                y: canvasOrigin.y + event.scrollingDeltaY / zoom
            )
        }
        needsLayout = true
        needsDisplay = true
        notifyViewportChanged()
    }

    override func magnify(with event: NSEvent) {
        let newZoom = (zoom * (1 + event.magnification))
            .clamped(to: Constants.canvasMinZoom...Constants.canvasMaxZoom)
        let mouseScreen = convert(event.locationInWindow, from: nil)
        let mouseCanvas = screenToCanvas(mouseScreen)
        zoom = newZoom
        canvasOrigin = CGPoint(
            x: mouseCanvas.x - mouseScreen.x / zoom,
            y: mouseCanvas.y - mouseScreen.y / zoom
        )
        needsLayout = true
        needsDisplay = true
        notifyViewportChanged()
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

        // 再绘制前景覆盖物（连线、绘制矩形、磁力对齐参考线）
        drawTemporaryConnection()
        drawDrawingRect()
        drawSnapGuidelines()
    }

    /// 白色背景 + 浅灰色网格线（对标 Maestri 产品样式）
    private func drawLineGrid(in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 白色背景填充
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(rect)

        // 网格线参数
        let gridSpacing: CGFloat = 16 * zoom
        let lineColor = NSColor(white: 0.90, alpha: 1).cgColor
        let lineWidth: CGFloat = 0.5

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

    // MARK: - 磁力对齐参考线绘制

    private func drawSnapGuidelines() {
        guard !dragGuidelines.isEmpty else { return }
        NSColor.systemBlue.withAlphaComponent(0.7).setStroke()
        for line in dragGuidelines {
            let path = NSBezierPath()
            path.lineWidth = 1.0
            path.setLineDash([4, 3], count: 2, phase: 0)
            if line.axis == .vertical {
                let screenX = canvasToScreen(CGPoint(x: line.position, y: 0)).x
                let screenStart = canvasToScreen(CGPoint(x: 0, y: line.start)).y
                let screenEnd = canvasToScreen(CGPoint(x: 0, y: line.end)).y
                path.move(to: CGPoint(x: screenX, y: screenStart))
                path.line(to: CGPoint(x: screenX, y: screenEnd))
            } else {
                let screenY = canvasToScreen(CGPoint(x: 0, y: line.position)).y
                let screenStart = canvasToScreen(CGPoint(x: line.start, y: 0)).x
                let screenEnd = canvasToScreen(CGPoint(x: line.end, y: 0)).x
                path.move(to: CGPoint(x: screenStart, y: screenY))
                path.line(to: CGPoint(x: screenEnd, y: screenY))
            }
            path.stroke()
        }
    }

    // MARK: - 绘制矩形预览

    private func drawDrawingRect() {
        guard isInDrawingMode, let start = drawingStartPoint, let current = drawingCurrentPoint else { return }
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        path.lineWidth = 1.5
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.systemBlue.withAlphaComponent(0.6).setStroke()
        NSColor.systemBlue.withAlphaComponent(0.05).setFill()
        path.stroke()
        path.fill()
    }

    // MARK: - 临时连线绘制（连线工具拖动时）

    private func drawTemporaryConnection() {
        guard let fromId = connectingFromNodeId,
              let fromView = nodeViews[fromId],
              let toPoint = connectionDragPoint else { return }
        let fromPoint = CGPoint(x: fromView.frame.midX, y: fromView.frame.midY)
        let path = NSBezierPath()
        path.move(to: fromPoint)
        path.line(to: toPoint)
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
        path.stroke()

        // 起点节点高亮
        NSColor.systemBlue.withAlphaComponent(0.3).setFill()
        let dot = NSBezierPath(ovalIn: fromView.frame.insetBy(dx: -3, dy: -3))
        dot.fill()
    }

    // MARK: - 变更通知

    private func notifyViewportChanged() {
        onViewportChanged?(canvasOrigin, zoom)
    }

    // MARK: - Finder 文件拖入（创建 Note 节点）

    /// 拖入 .md/.markdown/.txt 文件时回调（canvasFrame, filePath）
    var onFilesDropped: (([String], CGPoint) -> Void)?

    /// 注册拖放目标（在 setup() 调用）
    func registerDragTypes() {
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard containsMarkdownFiles(sender) else { return [] }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard containsMarkdownFiles(sender) else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let locScreen = convert(sender.draggingLocation, from: nil)
        let locCanvas = screenToCanvas(locScreen)
        let urls = extractMarkdownURLs(from: sender)
        guard !urls.isEmpty else { return false }
        let paths = urls.map { $0.path }
        onFilesDropped?(paths, locCanvas)
        return true
    }

    private func containsMarkdownFiles(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        return urls.contains { isMarkdownFile($0) }
    }

    private func extractMarkdownURLs(from sender: NSDraggingInfo) -> [URL] {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return []
        }
        return urls.filter { isMarkdownFile($0) }
    }

    private func isMarkdownFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown" || ext == "txt"
    }
}

// MARK: - Comparable clamped

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
