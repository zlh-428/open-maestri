import AppKit

/// Note 节点视图（暖黄色背景圆角卡片，顶部带 NOTE 标签）
final class NoteNodeView: BaseNodeView {

    /// 左上角 NOTE 类型标签
    private let typeLabel = NSTextField(labelWithString: "NOTE")

    override func setup() {
        super.setup()
        // 暖黄色卡片背景
        layer?.backgroundColor = NSColor(red: 1.0, green: 0.98, blue: 0.88, alpha: 1).cgColor
        layer?.borderColor = NSColor(red: 0.92, green: 0.86, blue: 0.62, alpha: 1).cgColor
        layer?.borderWidth = 1

        // Header 也用暖黄色系
        headerView.layer?.backgroundColor = NSColor(red: 0.98, green: 0.94, blue: 0.72, alpha: 1).cgColor
        headerLabel.textColor = NSColor(red: 0.45, green: 0.35, blue: 0.1, alpha: 1)

        setupTypeLabel()
    }

    private func setupTypeLabel() {
        typeLabel.font = .systemFont(ofSize: 9, weight: .bold)
        typeLabel.textColor = NSColor(red: 0.6, green: 0.5, blue: 0.2, alpha: 1)
        typeLabel.isBezeled = false
        typeLabel.drawsBackground = false
        typeLabel.isEditable = false
        typeLabel.isSelectable = false
        headerView.addSubview(typeLabel)
    }

    override func layout() {
        super.layout()
        let h: CGFloat = 28
        // NOTE 标签放在 header 右侧
        typeLabel.sizeToFit()
        let labelW = typeLabel.frame.width
        typeLabel.frame = CGRect(x: frame.width - labelW - 8, y: (h - 12) / 2, width: labelW, height: 12)
    }

    func setColor(hex: String) {
        if let components = parseHex(hex) {
            layer?.backgroundColor = NSColor(red: components.r, green: components.g, blue: components.b, alpha: 1).cgColor
        }
    }

    private func parseHex(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        return (CGFloat((val >> 16) & 0xFF) / 255, CGFloat((val >> 8) & 0xFF) / 255, CGFloat(val & 0xFF) / 255)
    }

    /// 移动到其他目录的回调（由 CanvasNodeRenderer 设置，传入新的目录 URL）
    var onMoveTo: ((URL) -> Void)?

    // MARK: - 右键菜单

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "复制节点", action: #selector(duplicateNote), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重命名", action: #selector(renameNote), keyEquivalent: ""))
        menu.addItem(.separator())
        let moveItem = NSMenuItem(title: "移动到…", action: #selector(moveNoteToDirectory), keyEquivalent: "")
        menu.addItem(moveItem)
        menu.addItem(.separator())
        let lockItem = NSMenuItem(title: isLocked ? "解锁" : "锁定",
                                  action: #selector(toggleLock), keyEquivalent: "")
        menu.addItem(lockItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "创建连接", action: #selector(startConnect), keyEquivalent: ""))
        menu.addItem(.separator())
        let closeItem = NSMenuItem(title: "删除", action: #selector(closeNote), keyEquivalent: "")
        let closeAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]
        closeItem.attributedTitle = NSAttributedString(string: "删除", attributes: closeAttrs)
        menu.addItem(closeItem)
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func duplicateNote() { onDuplicate?() }
    @objc private func renameNote() { startInlineRename() }
    @objc private func startConnect() { onConnect?() }

    @objc private func moveNoteToDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择目标目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "移动到这里"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.onMoveTo?(url)
        }
    }

    @objc private func toggleLock() {
        isLocked = !isLocked
        onLockToggle?(isLocked)
    }
    @objc private func closeNote() { onClose?() }
}
