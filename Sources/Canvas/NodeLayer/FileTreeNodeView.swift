import AppKit

/// FileTree 节点视图（白色面板 + Finder 风格 header 导航栏）
final class FileTreeNodeView: BaseNodeView {

    /// 导航栏按钮区域（前进/后退箭头图标）
    private let navBackButton = NSButton()
    private let navForwardButton = NSButton()

    override func setup() {
        super.setup()
        // 白色面板背景
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderColor = NSColor(white: 0.85, alpha: 1).cgColor
        layer?.borderWidth = 1

        // Header 使用浅灰色导航栏风格
        headerView.layer?.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor
        headerLabel.textColor = .labelColor
        headerLabel.font = .systemFont(ofSize: 12, weight: .medium)

        setupNavButtons()
    }

    private func setupNavButtons() {
        // 后退按钮
        navBackButton.bezelStyle = .inline
        navBackButton.isBordered = false
        navBackButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        navBackButton.contentTintColor = .secondaryLabelColor
        navBackButton.imageScaling = .scaleProportionallyDown
        headerView.addSubview(navBackButton)

        // 前进按钮
        navForwardButton.bezelStyle = .inline
        navForwardButton.isBordered = false
        navForwardButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")
        navForwardButton.contentTintColor = .secondaryLabelColor
        navForwardButton.imageScaling = .scaleProportionallyDown
        headerView.addSubview(navForwardButton)
    }

    override func layout() {
        super.layout()
        let h: CGFloat = 28
        // 导航按钮在右侧
        navForwardButton.frame = CGRect(x: frame.width - 26, y: (h - 16) / 2, width: 16, height: 16)
        navBackButton.frame = CGRect(x: frame.width - 46, y: (h - 16) / 2, width: 16, height: 16)
    }

    // MARK: - 右键菜单

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "重命名", action: #selector(renameTree), keyEquivalent: ""))
        menu.addItem(.separator())
        let lockItem = NSMenuItem(title: isLocked ? "解锁" : "锁定",
                                  action: #selector(toggleLock), keyEquivalent: "")
        menu.addItem(lockItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "删除", action: #selector(closeTree), keyEquivalent: ""))
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func renameTree() { startInlineRename() }
    @objc private func toggleLock() {
        isLocked = !isLocked
        onLockToggle?(isLocked)
    }
    @objc private func closeTree() { onClose?() }
}
