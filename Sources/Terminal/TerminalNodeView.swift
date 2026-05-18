import AppKit

/// 终端节点视图 - 浅色 header + 深色终端内容区域（匹配 Maestri UI 风格）
final class TerminalNodeView: BaseNodeView {

    // MARK: - 子视图

    /// 左侧圆形状态指示灯（idle=灰色，active=绿色 + 呼吸动画）
    private let statusDot = NSView()
    /// 数字角标（⌘+数字跳转时显示）
    private let numberBadge = NSTextField(labelWithString: "")
    private var pulseAnimation: CABasicAnimation?
    /// 滚动锁定指示器（⌘⇧B 锁定时显示）
    private let scrollLockBadge = NSTextField(labelWithString: "⏸")

    // MARK: - 状态

    var isIdle: Bool = true {
        didSet { updateStatus() }
    }

    var jumpNumber: Int? {
        didSet { updateNumberBadge() }
    }

    var isSelected: Bool = false {
        didSet { updateSelectionBorder() }
    }

    /// 是否锁定自动滚动（⌘⇧B 切换）；值变化时刷新锁定指示器
    var autoScrollLocked: Bool = false {
        didSet { updateScrollLockIndicator() }
    }

    /// 是否为 Maestro 管理器终端（显示星标图标）
    var showMaestroIndicator: Bool = false {
        didSet { updateMaestroIndicator() }
    }

    // MARK: - 回调

    // onClose 已提升到 BaseNodeView
    var onEdit: (() -> Void)?

    // MARK: - 初始化

    // Agent 类型图标（SF Symbol）
    private let agentIconView = NSImageView()
    // Maestro 模式图标（★ 星标）
    private let maestroIcon = NSTextField(labelWithString: "★")

    override func setup() {
        super.setup()

        // 终端节点整体样式：白色外壳包裹深色终端
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderColor = NSColor(white: 0.85, alpha: 1).cgColor
        layer?.borderWidth = 0.5

        // Header 使用浅灰色背景（匹配 Maestri 的浅色 header）
        headerView.layer?.backgroundColor = NSColor(white: 0.97, alpha: 1).cgColor
        headerLabel.textColor = NSColor(white: 0.2, alpha: 1)
        headerLabel.font = .systemFont(ofSize: 12, weight: .medium)

        setupStatusDot()
        setupNumberBadge()
        setupMaestroIcon()
        setupScrollLockBadge()
    }

    private func setupScrollLockBadge() {
        scrollLockBadge.font = .systemFont(ofSize: 9)
        scrollLockBadge.textColor = NSColor.systemOrange
        scrollLockBadge.alignment = .center
        scrollLockBadge.isHidden = true
        headerView.addSubview(scrollLockBadge)
    }

    private func setupStatusDot() {
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 5  // 10x10 圆形
        statusDot.layer?.backgroundColor = NSColor(white: 0.75, alpha: 1).cgColor
        headerView.addSubview(statusDot)
    }

    private func setupMaestroIcon() {
        maestroIcon.font = .systemFont(ofSize: 10)
        maestroIcon.textColor = NSColor.systemYellow
        maestroIcon.isHidden = true
        maestroIcon.alignment = .center
        headerView.addSubview(maestroIcon)
    }

    /// 更新 agent 图标（SF Symbol）和状态灯颜色
    func setAgentStyle(icon: String, colorHex: String) {
        // SF Symbol 图标
        if let image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            agentIconView.image = image
            agentIconView.contentTintColor = hexColor(colorHex)
            agentIconView.imageScaling = .scaleAxesIndependently
            if agentIconView.superview == nil {
                headerView.addSubview(agentIconView)
            }
            needsLayout = true
        }
        // 状态灯使用 agent 对应的颜色
        let accent = hexColor(colorHex)
        if !isIdle {
            statusDot.layer?.backgroundColor = accent.cgColor
        }
    }

    private func hexColor(_ hex: String) -> NSColor {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return .systemBlue }
        return NSColor(
            red: CGFloat((val >> 16) & 0xFF) / 255,
            green: CGFloat((val >> 8) & 0xFF) / 255,
            blue: CGFloat(val & 0xFF) / 255,
            alpha: 1
        )
    }

    private func setupNumberBadge() {
        numberBadge.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        numberBadge.textColor = NSColor(white: 0.5, alpha: 1)
        numberBadge.alignment = .center
        numberBadge.isHidden = true
        numberBadge.wantsLayer = true
        numberBadge.layer?.cornerRadius = 3
        numberBadge.layer?.backgroundColor = NSColor(white: 0.92, alpha: 1).cgColor
        headerView.addSubview(numberBadge)
    }

    // MARK: - 布局

    override func layout() {
        super.layout()
        let h = Self.headerHeight  // 使用基类的 headerHeight（32）

        // 左侧圆形状态指示灯
        let dotSize: CGFloat = 10
        let dotX: CGFloat = 10
        let dotY = (h - dotSize) / 2
        statusDot.frame = CGRect(x: dotX, y: dotY, width: dotSize, height: dotSize)

        // Maestro 图标紧跟状态灯后
        let maestroX: CGFloat = dotX + dotSize + 4
        maestroIcon.frame = CGRect(x: maestroX, y: (h - 14) / 2, width: 14, height: 14)

        // Agent 图标
        let agentX: CGFloat = showMaestroIndicator ? maestroX + 16 : dotX + dotSize + 6
        agentIconView.frame = CGRect(x: agentX, y: (h - 14) / 2, width: 14, height: 14)

        // header label 在图标之后
        let labelX = agentX + 18
        let badgeArea: CGFloat = 40  // 为右侧角标预留空间
        headerLabel.frame = CGRect(x: labelX, y: 6, width: frame.width - labelX - badgeArea, height: h - 12)

        // 数字角标在右侧（小巧的圆角矩形）
        let badgeW: CGFloat = 18
        let badgeH: CGFloat = 16
        numberBadge.frame = CGRect(x: frame.width - badgeW - 10, y: (h - badgeH) / 2, width: badgeW, height: badgeH)

        // 滚动锁定指示器在数字徽章左侧
        scrollLockBadge.frame = CGRect(x: frame.width - badgeW - 28, y: (h - 14) / 2, width: 14, height: 14)
    }

    // MARK: - 状态更新

    private func updateStatus() {
        if isIdle {
            statusDot.layer?.backgroundColor = NSColor(white: 0.75, alpha: 1).cgColor
            stopPulseAnimation()
        } else {
            statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
            startPulseAnimation()
        }
    }

    private func updateMaestroIndicator() {
        maestroIcon.isHidden = !showMaestroIndicator
        // Maestro 终端用金色边框区分
        if showMaestroIndicator {
            layer?.borderColor = NSColor.systemYellow.withAlphaComponent(0.6).cgColor
            layer?.borderWidth = 1.5
        } else if !isSelected {
            layer?.borderColor = NSColor(white: 0.85, alpha: 1).cgColor
            layer?.borderWidth = 0.5
        }
    }

    private func startPulseAnimation() {
        guard statusDot.layer?.animation(forKey: "pulse") == nil else { return }
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.3
        anim.duration = 0.8
        anim.autoreverses = true
        anim.repeatCount = .infinity
        statusDot.layer?.add(anim, forKey: "pulse")
    }

    private func stopPulseAnimation() {
        statusDot.layer?.removeAnimation(forKey: "pulse")
    }

    private func updateNumberBadge() {
        if let n = jumpNumber {
            numberBadge.stringValue = "\(n)"
            numberBadge.isHidden = false
        } else {
            numberBadge.isHidden = true
        }
        needsLayout = true
    }

    private func updateScrollLockIndicator() {
        scrollLockBadge.isHidden = !autoScrollLocked
        needsLayout = true
    }

    private func updateSelectionBorder() {
        // 选中效果由 BaseNodeView 统一在外层绘制虚线边框
        if !isSelected {
            layer?.borderColor = NSColor(white: 0.85, alpha: 1).cgColor
            layer?.borderWidth = 0.5
        }
    }

    // MARK: - 右键菜单

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "编辑终端", action: #selector(editTerminal), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "复制节点", action: #selector(duplicateNode), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重命名", action: #selector(renameNode), keyEquivalent: ""))
        menu.addItem(.separator())

        // Assign Role 子菜单
        let roleMenu = NSMenu()
        // "无角色"选项（清除角色）
        let clearItem = NSMenuItem(title: "无角色（清除）", action: #selector(clearRole), keyEquivalent: "")
        clearItem.target = self
        roleMenu.addItem(clearItem)
        if !availableRoles.isEmpty {
            roleMenu.addItem(.separator())
            for role in availableRoles {
                let item = NSMenuItem(title: role.name, action: #selector(assignRoleByTag(_:)), keyEquivalent: "")
                item.representedObject = role
                item.target = self
                roleMenu.addItem(item)
            }
        }
        let roleItem = NSMenuItem(title: "分配角色", action: nil, keyEquivalent: "")
        roleItem.submenu = roleMenu
        menu.addItem(roleItem)
        menu.addItem(.separator())

        let lockItem = NSMenuItem(title: isLocked ? "解锁" : "锁定", action: #selector(toggleLock), keyEquivalent: "")
        menu.addItem(lockItem)
        let scrollLockLabel = autoScrollLocked ? "解除滚动锁定" : "锁定滚动（⌘⇧B）"
        let scrollLockItem = NSMenuItem(title: scrollLockLabel, action: #selector(toggleScrollLock), keyEquivalent: "")
        menu.addItem(scrollLockItem)
        menu.addItem(.separator())
        // 创建连接
        menu.addItem(NSMenuItem(title: "创建连接", action: #selector(startConnect), keyEquivalent: ""))
        menu.addItem(.separator())
        let closeItem = NSMenuItem(title: "关闭", action: #selector(closeNode), keyEquivalent: "w")
        closeItem.keyEquivalentModifierMask = .command
        let closeAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]
        closeItem.attributedTitle = NSAttributedString(string: "关闭", attributes: closeAttrs)
        menu.addItem(closeItem)
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func clearRole() {
        onAssignRole?(nil)
    }

    @objc private func assignRoleByTag(_ sender: NSMenuItem) {
        guard let role = sender.representedObject as? RolePreset else { return }
        onAssignRole?(role)
    }

    @objc private func editTerminal() { onEdit?() }
    @objc private func duplicateNode() { onDuplicate?() }
    @objc private func renameNode() { startInlineRename() }
    @objc private func toggleLock() {
        isLocked = !isLocked
        onLockToggle?(isLocked)
    }
    @objc private func toggleScrollLock() {
        autoScrollLocked.toggle()
        onScrollLockToggle?(autoScrollLocked)
    }
    @objc private func startConnect() { onConnect?() }
    @objc private func closeNode() { onClose?() }
    /// 滚动锁定状态变更回调（由 CanvasNodeRenderer 绑定）
    var onScrollLockToggle: ((Bool) -> Void)?
    /// Assign Role 回调（rolePreset = nil 表示清除角色，立即重启终端）
    var onAssignRole: ((RolePreset?) -> Void)?
    /// 可用角色列表（由 CanvasNodeRenderer 从 AppState.preferences 注入）
    var availableRoles: [RolePreset] = []
    // onLockToggle 已提升到 BaseNodeView
    // onRename 已提升到 BaseNodeView
}
