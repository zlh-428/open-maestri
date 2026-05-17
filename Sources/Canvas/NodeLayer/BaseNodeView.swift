import AppKit

/// 画布节点基类 NSView
/// - 提供统一的 Header（标题栏）、拖拽移动、边角 Resize handle
/// - 所有具体节点（Terminal/Note/Portal/FileTree）继承此类
class BaseNodeView: NSView {
    // MARK: - 属性

    var nodeId: UUID?
    var isLocked: Bool = false

    var title: String = "" {
        didSet { headerLabel.stringValue = title }
    }

    // MARK: - 子视图

    let headerView = HeaderForwardingView()
    let headerLabel = NSTextField(labelWithString: "")
    let contentView = NSView()
    /// Header 底部分隔线
    private let headerSeparator = NSView()
    /// 右下角 Resize handle
    private let resizeHandle = NSView()
    /// 常驻于 contentView 之上的事件路由层：
    ///   - 节点未选中时：拦截 mouseDown，触发选中 + 初始化拖动
    ///   - 节点已选中时：移除自身，让事件穿透到终端/WebView 内容区
    ///   - 拖动期间：重新安装，全程拦截防止内容区消费拖动
    private lazy var contentEventRouter: ContentEventRouterView = {
        let v = ContentEventRouterView()
        v.autoresizingMask = [.width, .height]
        return v
    }()

    // MARK: - Resize 状态（移动拖拽由 canvas 层统一处理）

    fileprivate var isResizing = false
    fileprivate var resizeStartLocation: CGPoint?
    fileprivate var resizeStartFrame: CGRect?

    static let minNodeWidth: CGFloat = 160
    static let minNodeHeight: CGFloat = 80
    static let resizeHandleSize: CGFloat = 12

    // MARK: - 回调

    var onFrameChanged: ((CGRect) -> Void)?
    var onRename: ((String) -> Void)?
    var onFocusRequested: (() -> Void)?
    var onLockToggle: ((Bool) -> Void)?
    /// 节点被激活（点击时），用于更新 zIndex 使其置于最顶层
    var onActivated: (() -> Void)?
    /// 节点关闭/删除回调
    var onClose: (() -> Void)?
    /// 节点被点击回调（传入 NSEvent，由画布处理选中逻辑）
    var onNodeClicked: ((NSEvent) -> Void)?

    // MARK: - 行内重命名（基类通用实现）

    private var renameField: NSTextField?

    func startInlineRename() {
        let field = NSTextField(frame: headerLabel.frame)
        field.stringValue = title
        field.isEditable = true
        field.isBordered = true
        field.focusRingType = .none
        field.font = headerLabel.font
        field.target = self
        field.action = #selector(commitBaseRename(_:))
        headerView.addSubview(field)
        headerView.window?.makeFirstResponder(field)
        renameField = field
    }

    @objc private func commitBaseRename(_ sender: NSTextField) {
        let newName = sender.stringValue.trimmingCharacters(in: .whitespaces)
        if !newName.isEmpty {
            title = newName
            onRename?(newName)
        }
        sender.removeFromSuperview()
        renameField = nil
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

    func setup() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = false
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(white: 0.85, alpha: 1).cgColor
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: 2)
        layer?.shadowColor = NSColor.black.cgColor
        layer?.backgroundColor = NSColor.white.cgColor

        // Header
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor(white: 0.97, alpha: 1).cgColor
        // 仅上方两角圆角（与节点外壳圆角匹配）
        headerView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]  // macOS 坐标系下 top-left/top-right
        headerView.layer?.cornerRadius = 10
        headerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        headerLabel.textColor = NSColor(white: 0.25, alpha: 1)
        headerLabel.lineBreakMode = .byTruncatingTail
        headerView.addSubview(headerLabel)
        addSubview(headerView)

        // Header 底部分隔线
        headerSeparator.wantsLayer = true
        headerSeparator.layer?.backgroundColor = NSColor(white: 0.88, alpha: 1).cgColor
        headerView.addSubview(headerSeparator)

        // Content
        contentView.wantsLayer = true
        addSubview(contentView)

        // 内容区事件路由层（常驻 contentView 之上）
        contentEventRouter.baseNodeView = self
        addSubview(contentEventRouter, positioned: .above, relativeTo: contentView)

        // Resize handle（右下角标记，hover 时可见）
        resizeHandle.wantsLayer = true
        resizeHandle.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.2).cgColor
        resizeHandle.layer?.cornerRadius = 2
        resizeHandle.alphaValue = 0  // 默认隐藏，hover 时显示
        addSubview(resizeHandle)
    }

    /// Header 高度
    static let headerHeight: CGFloat = 32

    override func layout() {
        super.layout()
        let h = Self.headerHeight
        let hs = Self.resizeHandleSize
        headerView.frame = CGRect(x: 0, y: bounds.height - h, width: bounds.width, height: h)
        headerLabel.frame = CGRect(x: 8, y: 4, width: bounds.width - 16, height: h - 8)
        // Header 底部分隔线
        headerSeparator.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 0.5)
        contentView.frame = CGRect(x: 0, y: hs, width: bounds.width, height: bounds.height - h - hs)
        contentEventRouter.frame = contentView.frame
        resizeHandle.frame = CGRect(x: bounds.width - hs, y: 0, width: hs, height: hs)
        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
    }

    // MARK: - 回调（Option 拖拽复制）

    /// Option+拖拽时触发复制回调（传入新 frame 的画布坐标偏移）
    var onOptionDragDuplicate: (() -> Void)?
    fileprivate var hasTriggeredDuplicate = false

    // MARK: - 鼠标事件（移动 + Resize）

    override func mouseDown(with event: NSEvent) {
        // 无论是否锁定，都通知画布处理选中逻辑
        onNodeClicked?(event)

        guard !isLocked else { return }
        let loc = convert(event.locationInWindow, from: nil)
        hasTriggeredDuplicate = false

        if isInResizeHandle(loc) {
            isResizing = true
            resizeStartLocation = loc
            resizeStartFrame = frame
            NSCursor.crosshair.set()
        } else {
            onFocusRequested?()
            onActivated?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isLocked else { return }
        let loc = convert(event.locationInWindow, from: nil)

        if isResizing, let startLoc = resizeStartLocation, let startFrame = resizeStartFrame {
            // Resize：右下角拖拽（节点自身处理）
            let zoom = (superview as? CanvasViewportView)?.zoom ?? 1.0
            let dx = loc.x - startLoc.x
            let dy = loc.y - startLoc.y
            let newWidth = max(startFrame.width + dx, Self.minNodeWidth * zoom)
            let newHeight = max(startFrame.height - dy, Self.minNodeHeight * zoom)
            let newY = startFrame.maxY - newHeight
            frame = CGRect(x: startFrame.origin.x, y: newY, width: newWidth, height: newHeight)
        } else {
            // 拖动开始时安装拦截层，防止快速拖动时内容区消费事件
            installDragIntercept()
            // Option+拖拽复制检测（在节点内坐标系检测位移量）
            if event.modifierFlags.contains(.option) && !hasTriggeredDuplicate {
                let dx = abs(event.deltaX)
                let dy = abs(event.deltaY)
                if dx > 2 || dy > 2 {
                    hasTriggeredDuplicate = true
                    onOptionDragDuplicate?()
                }
            }
            // 移动事件向上传递给 canvas
            superview?.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isResizing {
            onFrameChanged?(frame)
        }
        isResizing = false
        resizeStartLocation = nil
        resizeStartFrame = nil
        NSCursor.arrow.set()
        removeDragIntercept()
        superview?.mouseUp(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if isInResizeHandle(loc) {
            NSCursor.crosshair.set()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                resizeHandle.animator().alphaValue = 1
            }
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            resizeHandle.animator().alphaValue = 0
        }
    }

    // MARK: - 滚动事件穿透控制 & 选中状态

    /// 节点是否被选中（由 CanvasViewportView 维护，renderer 在 sync 时更新）
    var isNodeSelected: Bool = false {
        didSet {
            guard oldValue != isNodeSelected else { return }
            updateSelectionOverlay()
            if isNodeSelected {
                contentEventRouter.isHidden = true
                print("[BaseNode] isNodeSelected=true, isHidden=true, firstResponder=\(type(of: window?.firstResponder))")
            } else {
                contentEventRouter.isHidden = false
                print("[BaseNode] isNodeSelected=false, isHidden=false")
                if contentEventRouter.superview == nil {
                    addSubview(contentEventRouter, positioned: .above, relativeTo: contentView)
                    contentEventRouter.frame = contentView.frame
                }
            }
        }
    }

    /// 选中虚线边框层（绘制在节点外围带 gap）
    private var selectionDashLayer: CAShapeLayer?

    /// 选中时在节点外层绘制蓝色虚线边框（带 8px 间距）
    private func updateSelectionOverlay() {
        if isNodeSelected {
            if selectionDashLayer == nil {
                let dash = CAShapeLayer()
                dash.name = "baseSelectionDash"
                dash.strokeColor = NSColor.systemBlue.cgColor
                dash.fillColor = NSColor.clear.cgColor
                dash.lineWidth = 2
                dash.lineDashPattern = [6, 4]
                layer?.addSublayer(dash)
                selectionDashLayer = dash
            }
            // 边框在节点外侧 8px 的位置
            let gap: CGFloat = 8
            let selectionRect = bounds.insetBy(dx: -gap, dy: -gap)
            selectionDashLayer?.path = CGPath(
                roundedRect: selectionRect,
                cornerWidth: layer!.cornerRadius + gap,
                cornerHeight: layer!.cornerRadius + gap,
                transform: nil
            )
            selectionDashLayer?.frame = bounds
        } else {
            selectionDashLayer?.removeFromSuperlayer()
            selectionDashLayer = nil
        }
    }

    override var frame: NSRect {
        didSet {
            if isNodeSelected {
                // frame 改变时更新选中边框路径
                updateSelectionOverlay()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    private func isInResizeHandle(_ point: CGPoint) -> Bool {
        isInResizeHandlePublic(point)
    }

    func isInResizeHandlePublic(_ point: CGPoint) -> Bool {
        let hs = Self.resizeHandleSize
        return point.x >= bounds.width - hs && point.y <= hs
    }

    // MARK: - 拖动拦截

    fileprivate func installDragIntercept() {
        guard !contentEventRouter.isDragging else { return }
        // 拖动时路由层扩展到整个节点，确保快速拖动时全区域拦截
        contentEventRouter.isHidden = false
        if contentEventRouter.superview == nil {
            addSubview(contentEventRouter, positioned: .above, relativeTo: nil)
        }
        contentEventRouter.frame = bounds
        contentEventRouter.isDragging = true
    }

    private func removeDragIntercept() {
        contentEventRouter.isDragging = false
        // 拖动结束：若节点仍选中则恢复透传模式，否则恢复到 contentView 覆盖并启用拦截
        if isNodeSelected {
            contentEventRouter.frame = contentView.frame
            contentEventRouter.isHidden = true
        } else {
            contentEventRouter.frame = contentView.frame
            contentEventRouter.isHidden = false
        }
    }
}

// MARK: - Header 事件转发视图

/// 节点头部视图，将鼠标事件转发给父节点（BaseNodeView），
/// 使得点击/拖动 header 区域与点击节点本体行为一致。
final class HeaderForwardingView: NSView {
    override func mouseDown(with event: NSEvent) {
        superview?.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        superview?.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        superview?.mouseUp(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        superview?.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        superview?.mouseExited(with: event)
    }
}

// MARK: - 内容区事件路由视图

/// 覆盖在 contentView 之上，负责两种职责：
///
/// **常驻模式**（节点未选中）：
///   拦截 mouseDown，触发选中 + 初始化拖动。
///
/// **拖动模式**（isDragging=true）：
///   扩展至整个节点，全程拦截 mouseDragged，防止终端/WebView 消费拖动事件。
final class ContentEventRouterView: NSView {
    weak var baseNodeView: BaseNodeView?
    var isDragging = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // 触发节点选中（等同于 BaseNodeView.mouseDown 中的 onNodeClicked）
        baseNodeView?.onNodeClicked?(event)

        guard let node = baseNodeView, !node.isLocked else { return }
        let loc = node.convert(event.locationInWindow, from: nil)
        node.hasTriggeredDuplicate = false

        if node.isInResizeHandlePublic(loc) {
            // resize handle：转给节点处理
            baseNodeView?.mouseDown(with: event)
        } else {
            node.onFocusRequested?()
            node.onActivated?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let node = baseNodeView, !node.isLocked else { return }
        if node.isResizing {
            baseNodeView?.mouseDragged(with: event)
        } else {
            // 拖动开始时安装拦截层，防止快速拖动时内容区消费事件
            node.installDragIntercept()
            if event.modifierFlags.contains(.option) && !node.hasTriggeredDuplicate {
                if abs(event.deltaX) > 2 || abs(event.deltaY) > 2 {
                    node.hasTriggeredDuplicate = true
                    node.onOptionDragDuplicate?()
                }
            }
            node.superview?.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        baseNodeView?.mouseUp(with: event)
    }
}

