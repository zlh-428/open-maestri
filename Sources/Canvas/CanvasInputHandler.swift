import AppKit
import OSLog

extension CanvasViewportView {

    // MARK: - 键盘事件

    override func keyDown(with event: NSEvent) {
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
        if event.keyCode == CanvasKeyCode.tab && flags == .control {
            cycleTerminalFocus(forward: true)
            return
        }

        // ⌃⇧Tab - 切换到上一个终端节点
        if event.keyCode == CanvasKeyCode.tab && flags == [.control, .shift] {
            cycleTerminalFocus(forward: false)
            return
        }

        // ⌘⇧B - 切换当前选中终端节点的滚动锁定
        if flags == [.command, .shift] && key == "b" {
            toggleAutoScrollLock()
            return
        }

        // Space - 进入平移模式
        if event.keyCode == CanvasKeyCode.space && !isSpaceHeld {
            isSpaceHeld = true
            NSCursor.openHand.set()
            return
        }

        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        // Space 释放 - 退出平移模式
        if event.keyCode == CanvasKeyCode.space {
            isSpaceHeld = false
            if case .panCanvas = interaction { interaction = .idle }
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
        // NSHostingView 迁移后 nodeViews 为空；跳转数字通过通知传递给 SwiftUI 层
        let terminalIds = currentNodes
            .filter { if case .terminal = $0.content { return true }; return false }
            .sorted { lhs, rhs in
                let lf = lhs.frame, rf = rhs.frame
                return lf.minX < rf.minX || (lf.minX == rf.minX && lf.minY < rf.minY)
            }
            .map { $0.id }
        var mapping: [UUID: Int] = [:]
        if visible {
            for (i, id) in terminalIds.enumerated() where i < 9 {
                mapping[id] = i + 1
            }
        }
        NotificationCenter.default.post(
            name: .canvasJumpNumbersAssigned,
            object: nil,
            userInfo: ["mapping": mapping]
        )
    }

    // MARK: - ⌘+数字 终端跳转

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ⌘= / ⌘+ — 放大（以视口中心为锚点）
        if flags == .command,
           let key = event.charactersIgnoringModifiers,
           key == "=" || key == "+" {
            zoomCanvas(delta: +Constants.canvasZoomStep)
            return true
        }

        // ⌘- — 缩小
        if flags == .command,
           let key = event.charactersIgnoringModifiers,
           key == "-" {
            zoomCanvas(delta: -Constants.canvasZoomStep)
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
    func zoomCanvas(delta: CGFloat) {
        applyZoom((zoom + delta).clamped(to: Constants.canvasMinZoom...Constants.canvasMaxZoom))
    }

    /// 以视口中心为锚点，设置绝对缩放值（如重置 100%）
    func zoomCanvas(toAbsolute target: CGFloat) {
        applyZoom(target.clamped(to: Constants.canvasMinZoom...Constants.canvasMaxZoom))
    }

    /// 以视口中心为锚点应用缩放值（内部实现）
    private func applyZoom(_ newZoom: CGFloat) {
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
        onViewportPanned?()
    }

    private func jumpToTerminal(number: Int) {
        // NSHostingView 迁移后改用 currentNodes + nodeCanvasFrames
        let sorted = currentNodes
            .filter { if case .terminal = $0.content { return true }; return false }
            .sorted { lhs, rhs in
                let lf = lhs.frame, rf = rhs.frame
                return lf.minX < rf.minX || (lf.minX == rf.minX && lf.minY < rf.minY)
            }
        guard number - 1 < sorted.count else { return }
        let targetNode = sorted[number - 1]
        // 聚焦到对应 TerminalView
        if let provider = TerminalProviderRegistry.shared.provider(for: targetNode.id),
           let tv = provider.terminalView {
            window?.makeFirstResponder(tv)
        }
        selectedNodeIds = [targetNode.id]
        // 平滑滚动视口使目标居中
        scrollToCanvasFrame(targetNode.frame)
    }

    // MARK: - ⌃Tab 终端循环切换

    /// 按画布横坐标排序，循环切换到下一个/上一个终端节点
    private func cycleTerminalFocus(forward: Bool) {
        let sorted = sortedTerminalNodes()
        guard !sorted.isEmpty else { return }

        // 找当前聚焦的终端索引
        let currentIndex: Int
        if let firstId = selectedNodeIds.first,
           let idx = sorted.firstIndex(where: { $0.id == firstId }) {
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
        selectedNodeIds = [target.id]
        if let provider = TerminalProviderRegistry.shared.provider(for: target.id),
           let tv = provider.terminalView {
            window?.makeFirstResponder(tv)
        }
        scrollToCanvasFrame(target.frame)
    }

    /// 按画布 x 坐标排序的终端节点列表
    private func sortedTerminalNodes() -> [CanvasNode] {
        currentNodes
            .filter { if case .terminal = $0.content { return true }; return false }
            .sorted { lhs, rhs in
                let lf = lhs.frame, rf = rhs.frame
                return lf.minX < rf.minX || (lf.minX == rf.minX && lf.minY < rf.minY)
            }
    }

    /// 反查节点视图对应的 UUID（供内部循环使用，兼容旧代码）
    func nodeId(forView view: NSView) -> UUID? {
        nodeId(for: view)
    }

    // MARK: - ⌘⇧B 滚动锁定

    /// 切换当前选中终端节点的自动滚动锁定状态
    private func toggleAutoScrollLock() {
        // NSHostingView 迁移后通过 TerminalProviderRegistry 操作，不依赖 TerminalNodeView
        let targetIds: [UUID] = selectedNodeIds.isEmpty
            ? currentNodes.filter { if case .terminal = $0.content { return true }; return false }.map { $0.id }
            : Array(selectedNodeIds)

        for id in targetIds {
            guard let provider = TerminalProviderRegistry.shared.provider(for: id) else { continue }
            let newLocked = !provider.isAutoScrollLocked
            provider.setAutoScrollLocked(newLocked)
        }
    }

    // MARK: - 聚焦到视口

    func focusSelectedNodeInViewport() {
        guard let firstId = selectedNodeIds.first,
              let frame = nodeCanvasFrames[firstId] else { return }
        scrollToCanvasFrame(frame)
        onFocusSelectedNode?()
    }

    /// 立即（无动画）跳转到指定画布 frame（内部同步使用）
    func scrollToCanvasFrame(_ canvasFrame: CGRect) {
        let newOriginX = canvasFrame.midX - (bounds.width / 2) / zoom
        let newOriginY = canvasFrame.midY - (bounds.height / 2) / zoom
        canvasOrigin = CGPoint(x: newOriginX, y: newOriginY)
        notifyViewportChanged()
        onViewportPanned?()
    }

    /// 平滑动画跳转到指定画布 frame（duration=0.35s easeInOut）
    func scrollToCanvasFrameAnimated(_ canvasFrame: CGRect, duration: TimeInterval = 0.35) {
        let targetOriginX = canvasFrame.midX - (bounds.width / 2) / zoom
        let targetOriginY = canvasFrame.midY - (bounds.height / 2) / zoom
        let targetOrigin = CGPoint(x: targetOriginX, y: targetOriginY)
        let startTime = CACurrentMediaTime()
        animateOrigin(from: canvasOrigin, to: targetOrigin, startTime: startTime, duration: duration)
    }

    /// 平滑动画跳转到指定视图（兼容旧调用：传 NSView）
    func scrollToViewAnimated(_ view: NSView, duration: TimeInterval = 0.35) {
        // 通过 viewToNodeId 反查 canvasFrame，避免依赖 nodeViews
        if let id = viewToNodeId[ObjectIdentifier(view)],
           let frame = nodeCanvasFrames[id] {
            scrollToCanvasFrameAnimated(frame, duration: duration)
        } else {
            // 降级：使用 view.frame（屏幕坐标）反算画布坐标
            let screenCenter = CGPoint(x: view.frame.midX, y: view.frame.midY)
            let canvasCenter = screenToCanvas(screenCenter)
            let targetOriginX = canvasCenter.x - (bounds.width / 2) / zoom
            let targetOriginY = canvasCenter.y - (bounds.height / 2) / zoom
            let startTime = CACurrentMediaTime()
            animateOrigin(from: canvasOrigin, to: CGPoint(x: targetOriginX, y: targetOriginY),
                          startTime: startTime, duration: duration)
        }
    }

    /// 逐帧插值 canvasOrigin（easeInOut 缓动），使用 Timer 60fps 驱动
    func animateOrigin(from: CGPoint, to: CGPoint, startTime: CFTimeInterval, duration: TimeInterval) {
        animationTimer?.invalidate()
        animationTimer = nil

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(elapsed / duration, 1.0)
            let eased = Self.easeInOut(progress)
            self.canvasOrigin = CGPoint(
                x: from.x + (to.x - from.x) * eased,
                y: from.y + (to.y - from.y) * eased
            )
            self.notifyViewportChanged()
            self.onViewportPanned?()
            if progress >= 1.0 {
                t.invalidate()
                self.animationTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    /// easeInOut 缓动函数
    static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
    }

    // MARK: - 平移模式

    func togglePanMode() {
        isPanMode = !isPanMode
        NSCursor.closedHand.set()
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
            // 触摸板两指平移：自然滚动（手指方向 = 内容移动方向）
            canvasOrigin = CGPoint(
                x: canvasOrigin.x - event.scrollingDeltaX / zoom,
                y: canvasOrigin.y - event.scrollingDeltaY / zoom
            )
        }
        needsLayout = true
        needsDisplay = true
        notifyViewportChanged()
        // 立即重渲染连线（不等 SwiftUI updateNSView 回路）
        onViewportPanned?()
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
        // 立即重渲染连线（不等 SwiftUI updateNSView 回路）
        onViewportPanned?()
    }
}
