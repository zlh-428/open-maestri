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

    // MARK: - Resize 状态（移动拖拽由 canvas 层统一处理）

    /// 8 方向 resize 枚举
    enum ResizeEdge {
        case right, left, top, bottom
        case topLeft, topRight, bottomLeft, bottomRight

        var cursor: NSCursor {
            switch self {
            case .right, .left:       return .resizeLeftRight
            case .top, .bottom:       return .resizeUpDown
            case .topLeft, .bottomRight: return .crosshair
            case .topRight, .bottomLeft: return .crosshair
            }
        }
    }

    static let minNodeWidth: CGFloat = 160
    static let minNodeHeight: CGFloat = 80
    /// 边缘热区宽度（像素，节点 bounds 坐标）
    static let resizeEdgeWidth: CGFloat = 10
    /// 角落热区大小
    static let resizeCornerSize: CGFloat = 20
    /// 兼容旧代码引用
    static let resizeHandleSize: CGFloat = resizeCornerSize

    // MARK: - 回调

    var onFrameChanged: ((CGRect) -> Void)?
    var onRename: ((String) -> Void)?
    var onFocusRequested: (() -> Void)?
    var onLockToggle: ((Bool) -> Void)?
    /// 节点被激活（点击时），用于更新 zIndex 使其置于最顶层
    var onActivated: (() -> Void)?
    /// 节点关闭/删除回调
    var onClose: (() -> Void)?
    /// 复制节点回调（右键菜单 Duplicate）
    var onDuplicate: (() -> Void)?
    /// 开始创建连接回调（右键菜单 Connect）
    var onConnect: (() -> Void)?

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

        // Resize handle（右下角角标，仅作视觉提示，交互由热区检测完成）
        resizeHandle.wantsLayer = true
        resizeHandle.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.35).cgColor
        resizeHandle.layer?.cornerRadius = 2
        resizeHandle.alphaValue = 0  // 默认隐藏，选中/hover 时显示
        addSubview(resizeHandle)
    }

    /// Header 高度
    static let headerHeight: CGFloat = 32

    override func layout() {
        super.layout()
        let h = Self.headerHeight
        let ew = Self.resizeEdgeWidth
        let w = bounds.width
        let bh = bounds.height
        headerView.frame = CGRect(x: 0, y: bh - h, width: w, height: h)
        headerLabel.frame = CGRect(x: 8, y: 4, width: w - 16, height: h - 8)
        headerSeparator.frame = CGRect(x: 0, y: 0, width: w, height: 0.5)
        // contentView 内缩以避免覆盖四边缘热区
        contentView.frame = CGRect(x: ew, y: ew, width: w - ew * 2, height: bh - h - ew)
        // 右下角视觉标记
        let cs: CGFloat = 10
        resizeHandle.frame = CGRect(x: w - cs, y: 0, width: cs, height: cs)
        contentView.needsLayout = true

        if isNodeSelected {
            updateSelectionOverlay()
        }
    }

    // MARK: - Resize 热区检测

    /// 根据点（bounds 坐标，y=0 在底部，isFlipped=false）返回对应的 resize 方向。
    func resizeEdge(at point: CGPoint) -> ResizeEdge? {
        let w = bounds.width
        let h = bounds.height
        let ew = Self.resizeEdgeWidth
        let cs = Self.resizeCornerSize
        let headerH = Self.headerHeight

        // header 区域不作 resize 热区（由节点拖动处理）
        if point.y > h - headerH { return nil }

        // top 边缘：紧贴 header 下方 ew 像素
        let topEdgeMaxY = h - headerH       // header 底部边缘（= contentView 顶部）
        let topEdgeMinY = topEdgeMaxY - ew  // header 下方 ew 像素

        // 角落检测（同时在 top/bottom 热区 + 左/右热区内）
        let inLeft  = point.x < cs
        let inRight = point.x > w - cs
        let inBot   = point.y < cs
        let inTop   = point.y > topEdgeMinY  // y 在 header 下方 ew 像素内

        if inTop && inLeft  { return .topLeft }
        if inTop && inRight { return .topRight }
        if inBot && inLeft  { return .bottomLeft }
        if inBot && inRight { return .bottomRight }

        // 四边热区
        if point.y > topEdgeMinY            { return .top }
        if point.y < ew                     { return .bottom }
        if point.x < ew                     { return .left }
        if point.x > w - ew                 { return .right }

        return nil
    }

    // MARK: - 滚动事件穿透控制 & 选中状态

    /// 节点是否被选中（由 CanvasViewportView 维护，renderer 在 sync 时更新）
    var isNodeSelected: Bool = false {
        didSet {
            guard oldValue != isNodeSelected else { return }
            updateSelectionOverlay()
            if !isNodeSelected {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    resizeHandle.animator().alphaValue = 0
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
            // selectionDashLayer 是 self.layer 的 sublayer，工作在 CALayer 坐标系中。
            // layer-backed NSView 中 layer.bounds == view.bounds（含 setBoundsSize 的效果），
            // 所以 sublayer 的 path 和 frame 应使用 view.bounds。
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

    // 注意：不在 frame/bounds didSet 中更新虚线框，因为 setBoundsSize 和 frame 赋值
    // 往往不是原子操作，didSet 触发时两者可能不同步。改由 layout() 统一更新。

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

    /// 兼容旧调用：判断是否在任意 resize 热区内
    func isInResizeHandlePublic(_ point: CGPoint) -> Bool {
        resizeEdge(at: point) != nil
    }
}

// MARK: - Header 事件转发视图

/// 节点头部视图。
/// 重构后：鼠标事件由画布层统一处理，不再需要转发。
/// rightMouseDown 通过继承链自然传递给 BaseNodeView。
final class HeaderForwardingView: NSView {}
