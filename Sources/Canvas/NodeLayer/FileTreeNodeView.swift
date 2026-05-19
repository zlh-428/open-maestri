import AppKit

/// FileTree 节点视图（对标产品风格：白色圆角卡片 + 顶部导航栏 + 底部搜索栏）
/// 交互模式：Finder 式导航——单击文件夹进入该目录，导航栏后退/前进切换目录
final class FileTreeNodeView: BaseNodeView {

    // MARK: - 顶部导航栏组件

    /// 导航栏容器
    private let navBar = NSView()
    /// 后退按钮
    private let navBackButton = NSButton()
    /// 前进按钮
    private let navForwardButton = NSButton()
    /// 当前目录名标签
    private let dirNameLabel = NSTextField(labelWithString: "")
    /// 视图切换下拉按钮
    private let viewModeButton = NSButton()

    // MARK: - 底部搜索栏

    private let searchBar = NSView()
    private let searchField = NSSearchField()

    // MARK: - 导航历史

    private var navHistory: [String] = []
    private var navIndex: Int = -1

    /// 文件树特有回调
    var onRevealInFinder: (() -> Void)?
    var onChangeRoot: (() -> Void)?
    /// 导航栏前进/后退/单击文件夹时直接切换到指定路径（不打开面板）
    var onNavigateToPath: ((String) -> Void)?
    /// 当前根目录路径（外部设置后更新导航栏标题）
    var currentRootPath: String = "" {
        didSet {
            let name = URL(fileURLWithPath: currentRootPath).lastPathComponent
            dirNameLabel.stringValue = name
            // 初始化导航历史
            if navHistory.isEmpty {
                navHistory = [currentRootPath]
                navIndex = 0
            }
        }
    }

    // MARK: - 布局常量

    private let navBarHeight: CGFloat = 32
    private let searchBarHeight: CGFloat = 32

    // MARK: - Setup

    override func setup() {
        super.setup()

        // 白色圆角卡片背景（不使用 masksToBounds 以保留选中虚线边框）
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 10
        layer?.borderColor = NSColor(white: 0.88, alpha: 1).cgColor
        layer?.borderWidth = 0.5
        // 注意：不设置 masksToBounds = true，否则会裁剪掉蓝色虚线选中边框

        // 隐藏 BaseNodeView 默认的 header（我们自定义导航栏）
        headerView.isHidden = true

        setupNavBar()
        setupSearchBar()
    }

    // MARK: - 导航栏

    private func setupNavBar() {
        navBar.wantsLayer = true
        navBar.layer?.backgroundColor = NSColor(white: 0.97, alpha: 1).cgColor
        // 导航栏上方圆角
        navBar.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        navBar.layer?.cornerRadius = 10
        addSubview(navBar)

        // 后退按钮
        configureNavButton(navBackButton, symbolName: "chevron.left", action: #selector(navBack))
        navBar.addSubview(navBackButton)

        // 前进按钮
        configureNavButton(navForwardButton, symbolName: "chevron.right", action: #selector(navForward))
        navBar.addSubview(navForwardButton)

        // 目录名标签
        dirNameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        dirNameLabel.textColor = .labelColor
        dirNameLabel.lineBreakMode = .byTruncatingMiddle
        dirNameLabel.alignment = .left
        dirNameLabel.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(dirNameLabel)

        // 视图切换下拉按钮
        viewModeButton.bezelStyle = .inline
        viewModeButton.isBordered = false
        viewModeButton.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "View Mode")
        viewModeButton.contentTintColor = .secondaryLabelColor
        viewModeButton.imageScaling = .scaleProportionallyDown
        viewModeButton.target = self
        viewModeButton.action = #selector(showViewModeMenu)
        navBar.addSubview(viewModeButton)

        updateNavButtonStates()
    }

    private func configureNavButton(_ button: NSButton, symbolName: String, action: Selector) {
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.contentTintColor = .secondaryLabelColor
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = action
    }

    // MARK: - 搜索栏

    private func setupSearchBar() {
        searchBar.wantsLayer = true
        searchBar.layer?.backgroundColor = NSColor(white: 0.97, alpha: 1).cgColor
        // 搜索栏下方圆角
        searchBar.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        searchBar.layer?.cornerRadius = 10
        addSubview(searchBar)

        searchField.placeholderString = "搜索"
        searchField.font = .systemFont(ofSize: 12)
        searchField.controlSize = .small
        searchField.focusRingType = .none
        searchField.target = self
        searchField.action = #selector(searchTextChanged)
        searchBar.addSubview(searchField)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height

        // 导航栏置顶
        navBar.frame = CGRect(x: 0, y: h - navBarHeight, width: w, height: navBarHeight)

        // 导航栏内部布局
        let btnSize: CGFloat = 20
        let btnY = (navBarHeight - btnSize) / 2
        navBackButton.frame = CGRect(x: 8, y: btnY, width: btnSize, height: btnSize)
        navForwardButton.frame = CGRect(x: 28, y: btnY, width: btnSize, height: btnSize)

        let labelX: CGFloat = 54
        let viewBtnWidth: CGFloat = 24
        let labelWidth = w - labelX - viewBtnWidth - 12
        dirNameLabel.frame = CGRect(x: labelX, y: btnY, width: max(labelWidth, 40), height: btnSize)

        viewModeButton.frame = CGRect(x: w - viewBtnWidth - 8, y: btnY, width: viewBtnWidth, height: btnSize)

        // 搜索栏置底（对齐底部边缘热区上方）
        let ew = BaseNodeView.resizeEdgeWidth
        searchBar.frame = CGRect(x: 0, y: ew, width: w, height: searchBarHeight)
        searchField.frame = CGRect(x: 8, y: 6, width: w - 16, height: searchBarHeight - 12)

        // 内容区域：内缩左右和底部边缘热区，使 contentEventRouter 不覆盖 resize 热区
        let contentY = ew + searchBarHeight
        let contentH = h - navBarHeight - searchBarHeight - ew
        contentView.frame = CGRect(x: ew, y: contentY, width: max(w - ew * 2, 0), height: max(contentH, 0))
    }

    // MARK: - 导航

    @objc private func navBack() {
        guard navIndex > 0 else { return }
        navIndex -= 1
        navigateToHistoryItem()
    }

    @objc private func navForward() {
        guard navIndex < navHistory.count - 1 else { return }
        navIndex += 1
        navigateToHistoryItem()
    }

    private func navigateToHistoryItem() {
        let path = navHistory[navIndex]
        currentRootPath = path
        updateNavButtonStates()
        // 导航栏切换：直接通知外部切换到该路径
        onNavigateToPath?(path)
    }

    private func updateNavButtonStates() {
        navBackButton.isEnabled = navIndex > 0
        navBackButton.contentTintColor = navIndex > 0 ? .labelColor : .tertiaryLabelColor
        navForwardButton.isEnabled = navIndex < navHistory.count - 1
        navForwardButton.contentTintColor = navIndex < navHistory.count - 1 ? .labelColor : .tertiaryLabelColor
    }

    /// 外部调用：push 新目录到导航栈
    func pushNavigation(to path: String) {
        // 如果和当前路径相同则不重复 push
        guard path != currentRootPath else { return }
        // 截断前进历史
        if navIndex < navHistory.count - 1 {
            navHistory = Array(navHistory.prefix(navIndex + 1))
        }
        navHistory.append(path)
        navIndex = navHistory.count - 1
        currentRootPath = path
        updateNavButtonStates()
    }

    // MARK: - 视图切换菜单

    @objc private func showViewModeMenu() {
        let menu = NSMenu()
        let listItem = NSMenuItem(title: "列表视图", action: #selector(switchToList), keyEquivalent: "")
        listItem.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)
        listItem.target = self
        menu.addItem(listItem)

        let gridItem = NSMenuItem(title: "图标视图", action: #selector(switchToGrid), keyEquivalent: "")
        gridItem.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        gridItem.target = self
        menu.addItem(gridItem)

        menu.addItem(.separator())

        let diffItem = NSMenuItem(title: "差异图", action: #selector(switchToDiff), keyEquivalent: "")
        diffItem.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil)
        diffItem.target = self
        menu.addItem(diffItem)

        menu.addItem(.separator())

        let showHidden = NSMenuItem(title: "显示隐藏文件", action: #selector(toggleHidden), keyEquivalent: "")
        showHidden.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        showHidden.target = self
        menu.addItem(showHidden)

        menu.addItem(.separator())

        let collapseAll = NSMenuItem(title: "全部折叠", action: #selector(collapseAll), keyEquivalent: "")
        collapseAll.image = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: nil)
        collapseAll.target = self
        menu.addItem(collapseAll)

        // 在按钮下方弹出菜单
        let point = NSPoint(x: viewModeButton.frame.minX, y: viewModeButton.frame.minY)
        menu.popUp(positioning: nil, at: point, in: navBar)
    }

    @objc private func switchToList() { /* 列表视图（默认） */ }
    @objc private func switchToGrid() { /* 图标视图 */ }
    @objc private func switchToDiff() { /* 差异图 */ }
    @objc private func toggleHidden() { /* 切换隐藏文件显示 */ }
    @objc private func collapseAll() { /* 全部折叠 */ }

    // MARK: - 搜索

    @objc private func searchTextChanged() {
        // TODO: 实现文件搜索过滤
        _ = searchField.stringValue
    }

    // MARK: - 右键菜单

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "在访达中显示", action: #selector(revealInFinder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "更改根目录", action: #selector(changeRootDir), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "复制节点", action: #selector(duplicateTree), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重命名", action: #selector(renameTree), keyEquivalent: ""))
        menu.addItem(.separator())
        let lockItem = NSMenuItem(title: isLocked ? "解锁" : "锁定",
                                  action: #selector(toggleLock), keyEquivalent: "")
        menu.addItem(lockItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "创建连接", action: #selector(startConnect), keyEquivalent: ""))
        menu.addItem(.separator())
        let closeItem = NSMenuItem(title: "删除", action: #selector(closeTree), keyEquivalent: "")
        let closeAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]
        closeItem.attributedTitle = NSAttributedString(string: "删除", attributes: closeAttrs)
        menu.addItem(closeItem)
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func revealInFinder() { onRevealInFinder?() }
    @objc private func changeRootDir() { onChangeRoot?() }
    @objc private func duplicateTree() { onDuplicate?() }
    @objc private func renameTree() { startInlineRename() }
    @objc private func startConnect() { onConnect?() }
    @objc private func toggleLock() {
        isLocked = !isLocked
        onLockToggle?(isLocked)
    }
    @objc private func closeTree() { onClose?() }
}
