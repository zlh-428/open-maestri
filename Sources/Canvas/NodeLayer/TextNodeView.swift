import AppKit

/// 画布文本标签节点（轻量级，无 header，直接编辑）
/// 双击进入编辑模式，点击外部退出编辑
final class TextNodeView: BaseNodeView {

    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private var isEditing = false

    /// 文本变化回调（传回最新文本内容）
    var onTextChanged: ((String) -> Void)?

    override func setup() {
        super.setup()

        // 透明背景，无边框（文本标签风格）
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.cornerRadius = 4

        // 隐藏 header（Text 节点不需要标题栏）
        headerView.isHidden = true

        setupTextView()
    }

    private func setupTextView() {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        textView.isEditable = false  // 默认不可编辑，双击进入
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.font = .systemFont(ofSize: 16)
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self

        scrollView.documentView = textView
        contentView.addSubview(scrollView)
    }

    override func layout() {
        super.layout()
        let contentFrame = contentView.bounds
        scrollView.frame = contentFrame
    }

    // MARK: - 配置

    func configure(text: String, fontSize: CGFloat, fontWeight: String, color: String, alignment: String) {
        textView.string = text
        textView.font = makeFont(size: fontSize, weight: fontWeight)
        textView.textColor = NSColor(hex: color) ?? .labelColor
        textView.alignment = parseAlignment(alignment)
    }

    private func makeFont(size: CGFloat, weight: String) -> NSFont {
        switch weight {
        case "bold":   return .systemFont(ofSize: size, weight: .bold)
        case "medium": return .systemFont(ofSize: size, weight: .medium)
        default:       return .systemFont(ofSize: size, weight: .regular)
        }
    }

    private func parseAlignment(_ alignment: String) -> NSTextAlignment {
        switch alignment {
        case "center": return .center
        case "right":  return .right
        default:       return .left
        }
    }

    // MARK: - 双击编辑

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            startEditing()
        } else {
            super.mouseDown(with: event)
        }
    }

    private func startEditing() {
        guard !isEditing else { return }
        isEditing = true
        textView.isEditable = true
        textView.window?.makeFirstResponder(textView)
        // 编辑时显示淡色背景
        layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.85).cgColor
    }

    func endEditing() {
        guard isEditing else { return }
        isEditing = false
        textView.isEditable = false
        layer?.backgroundColor = NSColor.clear.cgColor
        onTextChanged?(textView.string)
    }

    // MARK: - 右键菜单

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "编辑", action: #selector(editText), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "复制节点", action: #selector(duplicateText), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "创建连接", action: #selector(startConnect), keyEquivalent: ""))
        menu.addItem(.separator())
        let lockItem = NSMenuItem(title: isLocked ? "解锁" : "锁定",
                                  action: #selector(toggleLock), keyEquivalent: "")
        menu.addItem(lockItem)
        menu.addItem(.separator())
        let closeItem = NSMenuItem(title: "删除", action: #selector(closeText), keyEquivalent: "")
        let closeAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]
        closeItem.attributedTitle = NSAttributedString(string: "删除", attributes: closeAttrs)
        menu.addItem(closeItem)
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func editText() { startEditing() }
    @objc private func duplicateText() { onDuplicate?() }
    @objc private func startConnect() { onConnect?() }
    @objc private func toggleLock() {
        isLocked = !isLocked
        onLockToggle?(isLocked)
    }
    @objc private func closeText() { onClose?() }
}

// MARK: - NSTextViewDelegate

extension TextNodeView: NSTextViewDelegate {
    func textDidEndEditing(_ notification: Notification) {
        endEditing()
    }

    func textDidChange(_ notification: Notification) {
        onTextChanged?(textView.string)
    }
}
