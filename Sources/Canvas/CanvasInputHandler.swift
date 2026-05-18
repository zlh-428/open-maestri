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

    /// 反查节点视图对应的 UUID（供内部循环使用）
    func nodeId(forView view: NSView) -> UUID? {
        nodeId(for: view)
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

    func focusSelectedNodeInViewport() {
        guard let firstId = selectedNodeIds.first,
              let view = nodeViews[firstId] else { return }
        scrollToViewAnimated(view)
        onFocusSelectedNode?()
    }

    /// 立即（无动画）跳转到指定视图（内部同步使用）
    func scrollToView(_ view: NSView) {
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
            // 触摸板两指平移：手指方向 = 画布移动方向（自然滚动）
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
}
