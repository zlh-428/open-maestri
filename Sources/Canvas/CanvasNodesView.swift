import AppKit
import SwiftUI

// MARK: - 节点画布常量（替代 BaseNodeView 中的静态常量）
enum CanvasNodeConstants {
    static let headerHeight: CGFloat = 32
    static let footerHeight: CGFloat = 26
    static let minNodeWidth: CGFloat = 160
    static let minNodeHeight: CGFloat = 80
    static let resizeHandleSize: CGFloat = 12
    static let cornerRadius: CGFloat = 10
    static let selectionOutset: CGFloat = 3
}

// MARK: - 拖放目标 Environment Key

private struct DropTargetNodeIdKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var dropTargetNodeId: UUID? {
        get { self[DropTargetNodeIdKey.self] }
        set { self[DropTargetNodeIdKey.self] = newValue }
    }
}

// MARK: - CanvasNodesView
/// NSHostingView 子类，作为所有节点的 SwiftUI 容器。
/// hitTest 默认返回 self（不穿透内部 SwiftUI 视图到 AppKit 层），
/// 天然实现 Maestri 的 SwiftUIGestureBlocker 效果。
/// 所有鼠标/滚轮事件透传给父视图 CanvasViewportView 统一处理。
/// 例外：fileTree 节点的 NavBar 区域（List/Grid 切换、前进/后退等按钮）允许 SwiftUI 响应。
final class CanvasNodesView: NSHostingView<CanvasNodesSwiftUIView> {

    /// 注入 canvas 引用，用于 fileTree NavBar 区域的坐标判断
    weak var canvas: CanvasViewportView?

    // MARK: - hitTest 拦截

    /// 始终返回 self，确保所有鼠标事件经过 CanvasNodesView.mouseDown 路由。
    /// NSHostingView 在内部 SwiftUI 设 allowsHitTesting(false) 时可能返回 nil，
    /// 导致事件绕过本视图直接到达 CanvasViewportView，fileTree 等节点的程序化
    /// 点击转发逻辑失效（展开按钮、行选中、双击导航均不响应）。
    override func hitTest(_ point: NSPoint) -> NSView? {
        // 仅在点击位于本视图 bounds 内时拦截
        guard bounds.contains(point) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard let canvas else {
            nextResponder?.mouseDown(with: event)
            return
        }

        let loc = canvas.convert(event.locationInWindow, from: nil)
        if let (nodeId, hitKind) = fileTreeHitKind(at: loc, canvas: canvas) {
            switch hitKind {
            case .navBar:
                // NavBar 区域：精确分发按钮动作；只有弹出菜单时才消费事件，
                // 其余情况（后退/前进/标题空白）继续转发给 canvas 完成选中/拖拽
                if handleNavBarClick(nodeId: nodeId, loc: loc, event: event, canvas: canvas) {
                    return
                }
            case .content:
                // NSOutlineView/NSCollectionView 区域：先选中节点，再转发事件
                canvas.selectFileTreeNode(at: loc, modifiers: event.modifierFlags)
                forwardMouseDownToFileTreeContent(nodeId: nodeId, event: event)
                return
            case .swiftUI:
                // 纯 SwiftUI 区域（搜索栏等）：
                // 由于节点设置了 allowsHitTesting(false)，super.mouseDown 无法将事件路由给 SwiftUI TextField。
                // 因此手动查找点击位置下的 NSTextField 并激活第一响应者。
                canvas.selectFileTreeNode(at: loc, modifiers: event.modifierFlags)
                let windowPoint = event.locationInWindow
                let selfPoint = self.convert(windowPoint, from: nil)
                if let targetTextField = findTextField(at: selfPoint) {
                    self.window?.makeFirstResponder(targetTextField)
                } else {
                    super.mouseDown(with: event)
                }
                return
            }
        }

        nextResponder?.mouseDown(with: event)
    }

    /// 处理 navBar 区域点击：根据 x 坐标精确分发到后退/前进/菜单按钮。
    /// 返回 true 表示事件已被消费（菜单弹出），false 表示应继续交给 canvas 处理（选中/拖拽）。
    @discardableResult
    private func handleNavBarClick(
        nodeId: UUID, loc: CGPoint, event: NSEvent, canvas: CanvasViewportView
    ) -> Bool {
        guard let node = canvas.currentNodes.first(where: { $0.id == nodeId }) else { return false }
        let sf = canvas.canvasRectToScreen(node.frame)
        let localX    = (loc.x - sf.minX) / canvas.zoom
        let nodeWidth = node.frame.width

        // FileTreeNavigationBar 布局（从左到右）：
        //   leading(8) + 后退(28) + Divider(~1) + 前进(28) + 标题/Spacer + [git按钮] + 菜单胶囊 + trailing(8)
        //   菜单胶囊内容：list.dash(12) + spacing(4) + chevron.up.chevron.down(9) ≈ 25pt
        //   加 padding(.horizontal, 10) × 2 = 45pt 宽，trailing padding 8pt
        //   → 胶囊热区：menuMinX = nodeWidth - 53，menuMaxX = nodeWidth - 8
        let backRange    = 8.0...35.0 as ClosedRange<CGFloat>
        let forwardRange = 36.0...63.0 as ClosedRange<CGFloat>
        let menuMinX     = nodeWidth - 53.0
        let menuMaxX     = nodeWidth - 8.0

        if backRange.contains(localX) {
            FileTreeViewRegistry.shared.view(for: nodeId)?.onGoBack?()
            FileTreeGridViewRegistry.shared.view(for: nodeId)?.onGoBack?()
            return false   // 后退后仍允许 canvas 选中节点
        } else if forwardRange.contains(localX) {
            FileTreeViewRegistry.shared.view(for: nodeId)?.onGoForward?()
            FileTreeGridViewRegistry.shared.view(for: nodeId)?.onGoForward?()
            return false   // 前进后仍允许 canvas 选中节点
        } else if localX >= menuMinX && localX <= menuMaxX {
            showNavBarMenu(nodeId: nodeId, event: event)
            return true    // 菜单已弹出，消费事件，不再选中/拖拽
        }
        return false       // 标题/空白区域：交给 canvas 拖拽
    }

    /// 弹出 navBar 右侧菜单（列表/图标视图切换、显示隐藏文件等）。
    /// 不再转发 mouseDown 事件，直接构造并弹出 NSMenu，彻底避免递归。
    private func showNavBarMenu(nodeId: UUID, event: NSEvent) {
        guard let fileTreeView = FileTreeViewRegistry.shared.view(for: nodeId) else { return }

        let menu = NSMenu()

        let listItem = NSMenuItem(title: "filetree.menu.list_view".localized, action: #selector(menuSetListView(_:)), keyEquivalent: "")
        listItem.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)
        listItem.target = self
        listItem.representedObject = nodeId.uuidString
        menu.addItem(listItem)

        let gridItem = NSMenuItem(title: "filetree.menu.icon_view".localized, action: #selector(menuSetGridView(_:)), keyEquivalent: "")
        gridItem.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        gridItem.target = self
        gridItem.representedObject = nodeId.uuidString
        menu.addItem(gridItem)

        menu.addItem(.separator())

        let hiddenTitle = fileTreeView.showHiddenFiles ? "filetree.menu.hide_hidden_files".localized : "filetree.menu.show_hidden_files".localized
        let hiddenIcon  = fileTreeView.showHiddenFiles ? "eye.slash" : "eye"
        let hiddenItem = NSMenuItem(title: hiddenTitle, action: #selector(menuToggleHidden(_:)), keyEquivalent: "")
        hiddenItem.image = NSImage(systemSymbolName: hiddenIcon, accessibilityDescription: nil)
        hiddenItem.target = self
        hiddenItem.representedObject = nodeId.uuidString
        menu.addItem(hiddenItem)

        menu.addItem(.separator())

        let collapseItem = NSMenuItem(title: "filetree.menu.collapse_all".localized, action: #selector(menuCollapseAll(_:)), keyEquivalent: "")
        collapseItem.image = NSImage(systemSymbolName: "arrow.up.to.line", accessibilityDescription: nil)
        collapseItem.target = self
        collapseItem.representedObject = nodeId.uuidString
        menu.addItem(collapseItem)

        // NSMenu.popUp 是同步阻塞调用，其内部事件追踪通过 NSWindow.hitTest 确定命中视图。
        // 由于 CanvasNodesView 覆盖整个画布并在 hitTest 中始终返回 self，导致菜单追踪时
        // 找不到菜单窗口下的视图，菜单项显示灰色无法点击。
        // 解法：popUp 前临时将自身从父视图移除（popUp 同步阻塞，移除期间不会触发重绘/布局），
        // popUp 返回后立即加回，整个过程对用户不可见。
        let savedSuperview = superview
        let savedIndex = superview?.subviews.firstIndex(of: self)
        removeFromSuperview()
        defer {
            if let sv = savedSuperview {
                if let idx = savedIndex {
                    sv.subviews.insert(self, at: idx)
                } else {
                    sv.addSubview(self)
                }
            }
        }

        if let canvas = canvas {
            let canvasPoint = canvas.convert(event.locationInWindow, from: nil)
            menu.popUp(positioning: nil, at: canvasPoint, in: canvas)
        } else {
            let localPoint = self.convert(event.locationInWindow, from: nil)
            menu.popUp(positioning: nil, at: localPoint, in: self)
        }
    }

    @objc private func menuSetListView(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let nodeId = UUID(uuidString: idStr) else { return }
        NavBarMenuActionRelay.shared.setViewMode(.list, for: nodeId)
    }

    @objc private func menuSetGridView(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let nodeId = UUID(uuidString: idStr) else { return }
        NavBarMenuActionRelay.shared.setViewMode(.grid, for: nodeId)
    }

    @objc private func menuToggleHidden(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let nodeId = UUID(uuidString: idStr) else { return }
        NavBarMenuActionRelay.shared.toggleHidden(for: nodeId)
    }

    @objc private func menuCollapseAll(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let nodeId = UUID(uuidString: idStr) else { return }
        FileTreeViewRegistry.shared.view(for: nodeId)?.collapseAll()
    }

    /// 处理 fileTree 内容区的点击事件（程序化 API，不依赖 NSEvent 转发）
    ///
    /// 由于 NSOutlineView 通过 SwiftUI NSViewRepresentable 嵌入，经过 scaleEffect 变换后
    /// 其在 window 坐标系中的 frame 与视觉位置不一致，直接转发 NSEvent 会导致坐标错误。
    /// 因此计算出点击在内容区域内的本地坐标，通过程序化 API 执行操作。
    private func forwardMouseDownToFileTreeContent(nodeId: UUID, event: NSEvent) {
        guard let canvas = canvas,
              let node = canvas.currentNodes.first(where: { $0.id == nodeId }) else { return }

        // 计算点击在内容区域的本地坐标
        let canvasLoc = canvas.convert(event.locationInWindow, from: nil)
        let nodeScreenFrame = canvas.canvasRectToScreen(node.frame)
        let navBarH = (CanvasNodeConstants.headerHeight + 8) * canvas.zoom
        let contentTop = nodeScreenFrame.minY + navBarH

        // 相对于内容区域左上角的坐标（还原到 zoom=1 空间）
        let localX = (canvasLoc.x - nodeScreenFrame.minX) / canvas.zoom
        let localY = (canvasLoc.y - contentTop) / canvas.zoom
        let localPoint = NSPoint(x: localX, y: localY)

        // list 模式：程序化处理点击
        if let fileTreeView = FileTreeViewRegistry.shared.view(for: nodeId) {
            fileTreeView.handleClickAtLocalPoint(localPoint, clickCount: event.clickCount)
            return
        }
        // grid 模式：程序化处理点击
        if let gridView = FileTreeGridViewRegistry.shared.view(for: nodeId) {
            gridView.handleClickAtLocalPoint(localPoint, clickCount: event.clickCount)
            return
        }
    }

    /// fileTree 节点内的命中区域类型
    /// - navBar:  顶部导航栏（后退/前进/菜单按钮），高度 = headerHeight(32) + 8 = 40
    /// - content: NSOutlineView / NSCollectionView 区域，需转发给 AppKit 视图
    /// - swiftUI: 底部搜索栏等由 SwiftUI 渲染的区域，需用 super.mouseDown 正常路由
    private enum FileTreeContentHitKind { case navBar, content, swiftUI }

    private func fileTreeHitKind(
        at loc: CGPoint,
        canvas: CanvasViewportView
    ) -> (UUID, FileTreeContentHitKind)? {
        // loc 是 canvas 的 flipped 坐标系（isFlipped=true，y 向下，minY=顶边）
        for node in canvas.currentNodes {
            guard case .fileTree = node.content else { continue }
            let sf = canvas.canvasRectToScreen(node.frame)
            guard sf.contains(loc) else { continue }
            let localFromTop = loc.y - sf.minY
            let navBarH    = (CanvasNodeConstants.headerHeight + 8) * canvas.zoom
            // 底部 SwiftUI 区域 = 搜索栏(40) + git panel(0 或 120，由 extraBottomSwiftUIHeight 提供)
            let extraH = FileTreeViewRegistry.shared.view(for: node.id)?.extraBottomSwiftUIHeight ?? 0
            let swiftUIBottomH = (40 + extraH) * canvas.zoom
            let localFromBottom = sf.height - (loc.y - sf.minY)
            if localFromTop <= navBarH {
                return (node.id, .navBar)
            } else if localFromBottom <= swiftUIBottomH {
                // 底部纯 SwiftUI 区域（搜索栏 + git panel）：走 super.mouseDown 正常路由
                return (node.id, .swiftUI)
            } else {
                return (node.id, .content)
            }
        }
        return nil
    }

    /// 递归查找指定坐标下的 NSTextField（SwiftUI TextField 底层使用 NSTextField 渲染）
    private func findTextField(at point: CGPoint) -> NSTextField? {
        // 从 self 出发递归查找包含该点的 NSTextField
        return findTextField(in: self, at: point)
    }

    private func findTextField(in view: NSView, at pointInSelf: CGPoint) -> NSTextField? {
        for subview in view.subviews.reversed() {
            let pointInSubview = subview.convert(pointInSelf, from: self)
            guard subview.bounds.contains(pointInSubview) else { continue }
            if let textField = subview as? NSTextField, textField.isEditable || textField.isSelectable {
                return textField
            }
            if let found = findTextField(in: subview, at: pointInSelf) {
                return found
            }
        }
        return nil
    }

    override func mouseUp(with event: NSEvent) {
        nextResponder?.mouseUp(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        nextResponder?.mouseDragged(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        nextResponder?.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        nextResponder?.rightMouseUp(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        nextResponder?.mouseMoved(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

// MARK: - CanvasNodesSwiftUIView
/// 所有节点在 ZStack 中以 .frame + .position 布局。
/// 全部设 allowsHitTesting(false)，交互由 AppKit 层统一负责。
struct CanvasNodesSwiftUIView: View {
    /// 节点列表（调用方负责按 zIndex 升序排好，避免 body 中反复排序）
    let nodes: [CanvasNode]
    let canvasOrigin: CGPoint
    let zoom: CGFloat
    let selectedNodeIds: Set<UUID>
    let lockedNodeIds: Set<UUID>
    let workspace: WorkspaceManager?
    var dropTargetNodeId: UUID? = nil
    var onActivated: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onDuplicate: ((UUID) -> Void)?
    var onLockToggle: ((UUID, Bool) -> Void)?

    var body: some View {
        GeometryReader { _ in
            ZStack {
                ForEach(nodes, id: \.id) { node in
                    let posX = (node.frame.midX - canvasOrigin.x) * zoom
                    let posY = (node.frame.midY - canvasOrigin.y) * zoom
                    nodeView(for: node)
                        // 以原始画布尺寸渲染，内容不感知 zoom
                        .frame(width: node.frame.width, height: node.frame.height)
                        // scaleEffect 从中心缩放到屏幕尺寸，与 position center 语义匹配
                        .scaleEffect(zoom)
                        // position 与 hitTestCanvas/canvasRectToScreen 坐标系完全一致
                        .position(x: posX, y: posY)
                        // 所有几何变换（frame/scaleEffect/position）由 AppKit 层逐帧驱动，
                        // 必须切断所有动画传播路径（包括 zoom 变化触发的 scaleEffect 动画），
                        // 否则 SwiftUI 隐式动画会在拖拽/缩放时将节点插值到错误坐标导致消失。
                        // .animation(.none, value:) 只覆盖特定值的通道，
                        // .transaction 全量切断，是唯一可靠方案。
                        .transaction { $0.animation = nil }
                        // fileTree 节点的 hitTesting 由 CanvasNodesView.mouseDown 手动转发事件：
                        // 若设为 true，NSHostingView.hitTest 会穿透到内部 NSOutlineView，
                        // 导致 CanvasNodesView.mouseDown 不被调用，所有路由逻辑失效。
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // 忽略 safe area，使 GeometryReader 尺寸与 NSHostingView frame 完全一致
        // 否则 safe area insets 导致 SwiftUI .position() 坐标与 AppKit hitTest 坐标系不对齐
        .ignoresSafeArea()
        .environment(\.dropTargetNodeId, dropTargetNodeId)
    }

    @ViewBuilder
    private func nodeView(for node: CanvasNode) -> some View {
        let isSelected = selectedNodeIds.contains(node.id)
        let isLocked = lockedNodeIds.contains(node.id)
        switch node.content {
        case .terminal(let tc):
            TerminalNodeSwiftUIView(
                nodeId: node.id, content: tc, isSelected: isSelected, isLocked: isLocked,
                zoom: zoom, nodeSize: node.frame.size, workspace: workspace,
                onActivated: onActivated, onClose: onClose,
                onRename: onRename, onDuplicate: onDuplicate, onLockToggle: onLockToggle
            )
        case .stickyNote(let nc):
            NoteNodeSwiftUIView(
                nodeId: node.id, content: nc, isSelected: isSelected, isLocked: isLocked,
                zoom: zoom, workspace: workspace,
                onActivated: onActivated, onClose: onClose,
                onRename: onRename, onDuplicate: onDuplicate, onLockToggle: onLockToggle
            )
        case .portal(let pc):
            PortalNodeSwiftUIView(
                nodeId: node.id, content: pc, isSelected: isSelected, isLocked: isLocked,
                zoom: zoom,
                onActivated: onActivated, onClose: onClose,
                onRename: onRename, onDuplicate: onDuplicate, onLockToggle: onLockToggle
            )
        case .fileTree(let fc):
            FileTreeNodeSwiftUIView(
                nodeId: node.id, content: fc, isSelected: isSelected, isLocked: isLocked,
                zoom: zoom, workspace: workspace,
                onActivated: onActivated, onClose: onClose,
                onRename: onRename, onDuplicate: onDuplicate, onLockToggle: onLockToggle
            )
        case .text(let tc):
            TextNodeSwiftUIView(
                nodeId: node.id, content: tc, isSelected: isSelected, isLocked: isLocked,
                zoom: zoom,
                onActivated: onActivated, onClose: onClose,
                onRename: onRename, onDuplicate: onDuplicate, onLockToggle: onLockToggle
            )
        case .drawing(let dc):
            DrawingNodeSwiftUIView(
                nodeId: node.id, content: dc, isSelected: isSelected, isLocked: isLocked,
                zoom: zoom,
                onActivated: onActivated, onClose: onClose,
                onLockToggle: onLockToggle
            )
        }
    }
}
