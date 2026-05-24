import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 扩大展开按钮热区

/// 隐藏原生 disclosure triangle（改用 cell 内手动渲染的 chevron 图标）
private final class LargeDisclosureOutlineView: NSOutlineView {
    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        // 返回零区域，隐藏原生 disclosure triangle
        // 展开/折叠改由 handleClickAtLocalPoint 程序化处理 + cell 内的 chevron 图标指示状态
        return .zero
    }
}

/// File Tree List 视图（NSOutlineView 包装）
///
/// 交互模式（对标 Maestri File Tree）：
/// - 单击任意项：选中高亮（所有项目均可选中）
/// - 双击文件夹：通过 onNavigateTo 回调导航进入（Finder 式，不在视图内展开）
/// - 双击文件：通过 onFileOpened 回调，由外部用系统默认应用打开
/// - 右键：弹出上下文菜单（Create / Rename / Delete）
final class FileTreeOutlineNSView: NSView, NSOutlineViewDelegate, NSOutlineViewDataSource {

    // MARK: - Sub-views

    private let scrollView = NSScrollView()
    private let outlineView = LargeDisclosureOutlineView()
    private(set) var store: FileTreeStateStore

    /// 暴露 scrollView 引用，供 FileTreeOutlineView 转发滚动事件
    var scrollViewRef: NSScrollView { scrollView }

    /// 防止 reload 时频繁刷新
    private var pendingReloadWorkItem: DispatchWorkItem?

    /// 搜索过滤词（空字符串表示不过滤）
    var filterQuery: String = "" {
        didSet {
            guard filterQuery != oldValue else { return }
            if filterQuery.isEmpty {
                searchResults = []
                pendingSearchTask?.cancel()
                pendingSearchTask = nil
            } else {
                scheduleSearch(query: filterQuery)
            }
        }
    }

    /// 是否显示隐藏文件（以 . 开头的文件/目录）
    var showHiddenFiles: Bool = false

    /// 搜索结果（仅搜索模式下使用，后台 FileManager 枚举填充）
    private var searchResults: [FileTreeItem] = []

    /// 正在执行的搜索 Task（用于取消上一次未完成的搜索）
    private var pendingSearchTask: Task<Void, Never>?

    /// 当前数据源：搜索模式用 searchResults，否则用正常树根节点
    private var displayItems: [FileTreeItem] {
        if !filterQuery.isEmpty {
            return searchResults
        }
        var items = store.items
        if !showHiddenFiles {
            items = items.filter { !$0.name.hasPrefix(".") }
        }
        return items
    }

    /// 启动防抖搜索：300ms 内只执行最新一次
    private func scheduleSearch(query: String) {
        pendingSearchTask?.cancel()
        pendingSearchTask = Task { [weak self] in
            guard let self else { return }
            // 300ms 防抖
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let root = self.store.rootPath
            let hidden = self.showHiddenFiles
            let results = await Task.detached(priority: .userInitiated) {
                return FileTreeOutlineNSView.searchFiles(root: root, query: query, showHidden: hidden)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.filterQuery == query else { return }
                self.searchResults = results
                self.outlineView.reloadData()
            }
        }
    }

    /// 用 FileManager.enumerator 在后台递归搜索，返回扁平匹配列表
    private nonisolated static func searchFiles(root: String, query: String, showHidden: Bool) -> [FileTreeItem] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: showHidden ? [] : [.skipsHiddenFiles]
        ) else { return [] }

        var results: [FileTreeItem] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.localizedCaseInsensitiveContains(query) else { continue }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            results.append(FileTreeItem(
                id: url.path,
                name: name,
                isDirectory: isDir.boolValue,
                children: nil
            ))
            if results.count >= 200 { break }  // 防止结果爆炸
        }
        return results
    }

    // MARK: - Callbacks

    /// 双击/单击文件夹时导航进入的回调（传入目录绝对路径）
    var onNavigateTo: ((String) -> Void)?
    /// 双击文件时打开的回调
    var onFileOpened: ((String) -> Void)?
    /// Git 分支加载完成回调
    var onBranchLoaded: ((String) -> Void)?
    /// 任意点击时通知 Canvas 选中此节点
    var onTapped: (() -> Void)?

    // MARK: - Init

    init(store: FileTreeStateStore) {
        self.store = store
        super.init(frame: .zero)
        setupViews()
        reloadBranch()
        Task { @MainActor [weak self] in
            await store.reload()
            self?.outlineView.reloadData()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupViews() {
        // ── OutlineView 配置 ──
        let col = NSTableColumn(identifier: .init("name"))
        col.title = ""
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col
        outlineView.headerView = nil
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.rowHeight = 32
        outlineView.indentationPerLevel = 20
        outlineView.selectionHighlightStyle = .regular
        outlineView.style = .plain
        outlineView.focusRingType = .none
        outlineView.target = self
        outlineView.action = #selector(handleSingleClick)
        outlineView.doubleAction = #selector(handleDoubleClick)

        // 允许拖拽（文件拖到 Terminal / 画布）
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)

        // 右键菜单
        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

        // ── ScrollView 配置 ──
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
    }

    // MARK: - 外部刷新

    func reloadData() {
        scheduleReload()
    }

    func updateStore(_ newStore: FileTreeStateStore) {
        store = newStore
        scheduleReload()
        reloadBranch()
    }

    func reloadBranch() {
        let path = store.rootPath
        let callback = onBranchLoaded  // 捕获值类型快照，避免 SendableClosureCaptures 警告
        Task.detached(priority: .utility) {
            let provider = GitStatusProvider(workingDirectory: path)
            guard provider.isGitRepository,
                  let branch = try? provider.currentBranch() else {
                await MainActor.run { callback?("") }
                return
            }
            await MainActor.run { callback?(branch) }
        }
    }

    /// 防抖 reload：合并 100ms 内的多次调用；非搜索模式下 reload 后恢复展开状态
    private func scheduleReload() {
        pendingReloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.outlineView.reloadData()
            // 搜索模式不需要恢复展开状态（扁平列表）
            guard self.filterQuery.isEmpty else { return }
            self.restoreExpandedPaths()
        }
        pendingReloadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    /// 将 store.expandedPaths 中记录的路径在 NSOutlineView 中重新展开
    private func restoreExpandedPaths() {
        guard !store.expandedPaths.isEmpty else { return }
        // 按路径深度升序展开，确保父节点先于子节点展开
        let sorted = store.expandedPaths.sorted { $0.count < $1.count }
        for path in sorted {
            if let item = findItem(path: path, in: store.items) {
                outlineView.expandItem(item)
            }
        }
    }

    /// 在 items 树中按路径查找 FileTreeItem
    private func findItem(path: String, in items: [FileTreeItem]) -> FileTreeItem? {
        for item in items {
            if item.id == path { return item }
            if let children = item.children, let found = findItem(path: path, in: children) {
                return found
            }
        }
        return nil
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return displayItems.count }
        // 搜索模式：扁平列表，不展示子层级
        guard filterQuery.isEmpty else { return 0 }
        guard let fi = item as? FileTreeItem, fi.isDirectory else { return 0 }
        if let children = fi.children {
            let visible = showHiddenFiles ? children : children.filter { !$0.name.hasPrefix(".") }
            return visible.count
        }
        // 子项尚未加载：返回 1（占位）让 NSOutlineView 允许展开，
        // 展开后 outlineViewItemDidExpand 会异步加载并 reloadItem 替换为真实数量
        return 1
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil, index < displayItems.count { return displayItems[index] }
        guard let fi = item as? FileTreeItem else { return NSNull() }
        // children 已加载
        if let children = fi.children {
            let visible = showHiddenFiles ? children : children.filter { !$0.name.hasPrefix(".") }
            if index < visible.count { return visible[index] }
            return NSNull()
        }
        // 占位行：返回 fi 自身作为临时占位（reloadItem 后会被替换）
        // 这里返回 NSNull 也可以，NSOutlineView 在 viewFor 里会得到 nil 并跳过
        return NSNull()
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard filterQuery.isEmpty else { return false }
        guard let fi = item as? FileTreeItem else { return false }
        return fi.isDirectory
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let fi = item as? FileTreeItem else { return nil }
        return makeCell(for: fi, in: outlineView)
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return true   // 所有项目均可选中
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        // 使用自定义 row view 强制 emphasized 状态，
        // 确保即使 outlineView 未获得 first responder（嵌入画布场景），
        // 选中行也始终绘制系统标准蓝色背景（而非灰色非活跃态）
        let rowId = NSUserInterfaceItemIdentifier("FileTreeRow")
        if let existing = outlineView.makeView(withIdentifier: rowId, owner: self) as? EmphasizedRowView {
            return existing
        }
        let rowView = EmphasizedRowView()
        rowView.identifier = rowId
        return rowView
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return filterQuery.isEmpty ? 32 : 46
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let fi = notification.userInfo?["NSObject"] as? FileTreeItem else { return }
        store.expandedPaths.insert(fi.id)
        // 更新 chevron 方向
        updateChevron(for: fi, expanded: true)
        // 若子项尚未加载，异步加载后刷新
        guard fi.children == nil else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.store.loadChildren(for: fi.id)
            // 加载完毕后完整刷新 outline 并重新展开该项
            // 注意：reloadItem(_:reloadChildren:) 在某些情况下不会重新查询 numberOfChildren，
            // 因此改用 reloadData() 确保数据源完全同步
            self.outlineView.reloadData()
            self.outlineView.expandItem(fi)
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let fi = notification.userInfo?["NSObject"] as? FileTreeItem else { return }
        store.expandedPaths.remove(fi.id)
        // 更新 chevron 方向
        updateChevron(for: fi, expanded: false)
    }

    /// 更新指定 item 对应行的 chevron 图标方向
    private func updateChevron(for item: FileTreeItem, expanded: Bool) {
        let row = outlineView.row(forItem: item)
        guard row >= 0, let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView else { return }
        if let chevron = cell.viewWithTag(Self.chevronTag) as? NSImageView {
            let symbolName = expanded ? "chevron.down" : "chevron.right"
            chevron.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        }
    }

    // MARK: - 鼠标事件

    override func mouseDown(with event: NSEvent) {
        // 通知 Canvas 选中此 fileTree 节点（在 AppKit hit-test 直接路由到 NSOutlineView 时
        // CanvasNodesView.mouseDown 不会被调用，需要在此主动触发选中）
        onTapped?()
        super.mouseDown(with: event)
    }

    // MARK: - 单击/双击处理

    /// 单击：仅选中高亮行，不触发任何导航
    @objc private func handleSingleClick() {
        // NSOutlineView 会自动处理选中高亮，无需额外逻辑
        _ = outlineView.clickedRow
    }

    /// 双击处理：
    ///  - 文件夹 → Finder 式导航进入子目录（通过 onNavigateTo 回调）
    ///  - 文件   → 通过回调用默认应用打开
    @objc private func handleDoubleClick() {
        let row = outlineView.clickedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? FileTreeItem else { return }

        if item.isDirectory {
            onNavigateTo?(item.id)
        } else {
            onFileOpened?(item.id)
        }
    }

    /// 折叠所有展开的项目
    func collapseAll() {
        outlineView.collapseItem(nil, collapseChildren: true)
        store.expandedPaths.removeAll()
    }

    // MARK: - 程序化点击处理（由 CanvasNodesView 调用）

    /// 根据本地坐标执行点击操作（单击选中/展开折叠，双击导航/打开）
    /// - Parameters:
    ///   - localPoint: 相对于 outlineView 左上角的坐标（y 向下）
    ///   - clickCount: 1=单击, 2=双击
    func handleClickAtLocalPoint(_ localPoint: NSPoint, clickCount: Int) {
        // 计算行号：localPoint.y / rowHeight（考虑 scrollView 的 contentOffset）
        let scrollOffset = scrollView.contentView.bounds.origin
        let adjustedPoint = NSPoint(x: localPoint.x + scrollOffset.x, y: localPoint.y + scrollOffset.y)
        let row = outlineView.row(at: adjustedPoint)

        guard row >= 0, let item = outlineView.item(atRow: row) as? FileTreeItem else {
            // 点击空白区域：取消选中
            outlineView.deselectAll(nil)
            return
        }

        // 计算 disclosure（chevron）热区
        // Cell 布局：[缩进 level*20] + [chevron 16pt] + [gap 2pt] + [icon 20pt] + [gap 6pt] + [text]
        let rowRect = outlineView.rect(ofRow: row)
        let level = outlineView.level(forRow: row)
        // 缩进 + chevron(16) + gap(2) + icon(20) = 缩进 + 38，覆盖到 icon 右边缘
        let disclosureMaxX = CGFloat(level) * outlineView.indentationPerLevel + 38
        let isInDisclosureZone = item.isDirectory && (adjustedPoint.x - rowRect.minX) < disclosureMaxX

        if clickCount >= 2 {
            if isInDisclosureZone {
                // 双击在 disclosure 区域：仅展开/折叠，不触发导航（避免与展开操作冲突）
                if outlineView.isItemExpanded(item) {
                    outlineView.collapseItem(item)
                } else {
                    outlineView.expandItem(item)
                }
            } else {
                // 双击在非 disclosure 区域：目录导航进入 / 文件打开
                if item.isDirectory {
                    onNavigateTo?(item.id)
                } else {
                    onFileOpened?(item.id)
                }
            }
            return
        }

        // 单击：disclosure 区域切换展开/折叠
        if isInDisclosureZone {
            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item)
            } else {
                outlineView.expandItem(item)
            }
        }

        // 选中行
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        onTapped?()
    }

    // MARK: - 拖拽支持

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let fi = item as? FileTreeItem else { return nil }
        return URL(fileURLWithPath: fi.id) as NSURL
    }

    // MARK: - Cell 构建

    private func makeCell(for fi: FileTreeItem, in outlineView: NSOutlineView) -> NSView {
        let cellId = NSUserInterfaceItemIdentifier("FileCell")
        let cell: NSTableCellView

        if let existing = outlineView.makeView(withIdentifier: cellId, owner: self) as? NSTableCellView {
            cell = existing
        } else {
            cell = buildCellTemplate()
        }

        configureCellContents(cell, with: fi, in: outlineView)
        return cell
    }

    /// chevron 标识用的 tag
    private static let chevronTag = 9999
    /// 副标题路径标签的 tag（搜索模式下显示相对路径）
    private static let subtitleTag = 9998

    private func buildCellTemplate() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("FileCell")

        let chevron = NSImageView()
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.imageScaling = .scaleProportionallyDown
        chevron.tag = Self.chevronTag
        cell.addSubview(chevron)

        let imgView = NSImageView()
        imgView.translatesAutoresizingMaskIntoConstraints = false
        imgView.imageScaling = .scaleProportionallyDown
        cell.addSubview(imgView)
        cell.imageView = imgView

        // 文件名主标题
        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = .systemFont(ofSize: 13)
        textField.lineBreakMode = .byTruncatingMiddle
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cell.addSubview(textField)
        cell.textField = textField

        // 副标题：搜索结果下方显示相对路径
        let subtitle = NSTextField(labelWithString: "")
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitle.tag = Self.subtitleTag
        cell.addSubview(subtitle)

        NSLayoutConstraint.activate([
            chevron.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            chevron.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 16),
            chevron.heightAnchor.constraint(equalToConstant: 16),

            imgView.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 2),
            imgView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imgView.widthAnchor.constraint(equalToConstant: 20),
            imgView.heightAnchor.constraint(equalToConstant: 20),

            textField.leadingAnchor.constraint(equalTo: imgView.trailingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            textField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),

            subtitle.leadingAnchor.constraint(equalTo: textField.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            subtitle.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 1),
        ])

        return cell
    }

    private func configureCellContents(_ cell: NSTableCellView, with fi: FileTreeItem, in outlineView: NSOutlineView) {
        let isSearching = !filterQuery.isEmpty

        // 副标题：搜索模式下显示相对于 rootPath 的路径，否则隐藏
        if let subtitle = cell.viewWithTag(Self.subtitleTag) as? NSTextField {
            if isSearching {
                let root = store.rootPath
                let relative = fi.id.hasPrefix(root)
                    ? String(fi.id.dropFirst(root.count + 1))
                    : fi.id
                subtitle.stringValue = relative
                subtitle.isHidden = false
            } else {
                subtitle.stringValue = ""
                subtitle.isHidden = true
            }
        }

        cell.textField?.stringValue = fi.name
        cell.imageView?.image = fileIcon(for: fi)

        if let chevron = cell.viewWithTag(Self.chevronTag) as? NSImageView {
            // 搜索模式下扁平列表，不显示展开指示器
            if !isSearching && fi.isDirectory {
                chevron.isHidden = false
                let symbolName = outlineView.isItemExpanded(fi) ? "chevron.down" : "chevron.right"
                chevron.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
                chevron.contentTintColor = .secondaryLabelColor
            } else {
                chevron.isHidden = true
                chevron.image = nil
            }
        }

        switch fi.gitStatus {
        case .modified:   cell.textField?.textColor = .systemOrange
        case .added, .untracked: cell.textField?.textColor = .systemGreen
        case .deleted:    cell.textField?.textColor = .systemRed
        default:          cell.textField?.textColor = .labelColor
        }
    }

    private func fileIcon(for item: FileTreeItem) -> NSImage {
        if item.isDirectory {
            return NSWorkspace.shared.icon(for: UTType.folder)
        }
        return NSWorkspace.shared.icon(forFile: item.id)
    }
}

// MARK: - 右键菜单（NSMenuDelegate）

extension FileTreeOutlineNSView: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let row = outlineView.clickedRow
        guard row >= 0 else {
            // 点击空白区域：只提供创建选项
            menu.addItem(makeMenuItem(
                title: "filetree.menu.new_file".localized,
                icon: "doc.badge.plus",
                action: #selector(newFile)
            ))
            menu.addItem(makeMenuItem(
                title: "filetree.menu.new_folder".localized,
                icon: "folder.badge.plus",
                action: #selector(newFolder)
            ))
            return
        }

        // 选中点击的行
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        guard let item = outlineView.item(atRow: row) as? FileTreeItem else { return }

        if item.isDirectory {
            menu.addItem(makeMenuItem(
                title: "filetree.menu.open_folder".localized,
                icon: "arrow.forward",
                action: #selector(openInFinder),
                representedObject: item.id
            ))
            menu.addItem(.separator())
            menu.addItem(makeMenuItem(
                title: "filetree.menu.new_file".localized,
                icon: "doc.badge.plus",
                action: #selector(newFile),
                representedObject: item.id
            ))
            menu.addItem(makeMenuItem(
                title: "filetree.menu.new_folder".localized,
                icon: "folder.badge.plus",
                action: #selector(newFolder),
                representedObject: item.id
            ))
        } else {
            menu.addItem(makeMenuItem(
                title: "filetree.menu.open".localized,
                icon: "arrow.up.right",
                action: #selector(openFile),
                representedObject: item.id
            ))
            menu.addItem(makeMenuItem(
                title: "filetree.menu.reveal_in_finder".localized,
                icon: "magnifyingglass",
                action: #selector(openInFinder),
                representedObject: item.id
            ))
        }

        menu.addItem(.separator())
        menu.addItem(makeMenuItem(
            title: "filetree.menu.rename".localized,
            icon: "pencil",
            action: #selector(renameItem),
            representedObject: item.id
        ))
        menu.addItem(.separator())

        let deleteItem = makeMenuItem(
            title: "filetree.menu.delete".localized,
            icon: "trash",
            action: #selector(deleteItem),
            representedObject: item.id
        )
        deleteItem.attributedTitle = NSAttributedString(
            string: "filetree.menu.delete".localized,
            attributes: [.foregroundColor: NSColor.systemRed]
        )
        menu.addItem(deleteItem)
    }

    private func makeMenuItem(
        title: String,
        icon: String,
        action: Selector,
        representedObject: Any? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        item.target = self
        item.representedObject = representedObject
        return item
    }

    // MARK: - Menu Actions

    @objc private func openFile(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func openInFinder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let url = URL(fileURLWithPath: path)
        // 文件夹 → 导航进入；文件 → Finder 高亮
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        if isDir.boolValue {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func newFile(_ sender: NSMenuItem) {
        let parentPath: String
        if let p = sender.representedObject as? String {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: p, isDirectory: &isDir)
            parentPath = isDir.boolValue ? p : (p as NSString).deletingLastPathComponent
        } else {
            parentPath = store.rootPath
        }
        presentInlineRename(parentPath: parentPath, isFolder: false)
    }

    @objc private func newFolder(_ sender: NSMenuItem) {
        let parentPath: String
        if let p = sender.representedObject as? String {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: p, isDirectory: &isDir)
            parentPath = isDir.boolValue ? p : (p as NSString).deletingLastPathComponent
        } else {
            parentPath = store.rootPath
        }
        presentInlineRename(parentPath: parentPath, isFolder: true)
    }

    @objc private func renameItem(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let name = URL(fileURLWithPath: path).lastPathComponent
        let parent = (path as NSString).deletingLastPathComponent
        presentRenameAlert(currentName: name, parent: parent, oldPath: path)
    }

    @objc private func deleteItem(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let name = URL(fileURLWithPath: path).lastPathComponent
        let alert = NSAlert()
        alert.messageText = String(format: "filetree.delete.confirm_title".localized, name)
        alert.informativeText = "filetree.delete.confirm_message".localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: "filetree.menu.delete".localized)
        alert.addButton(withTitle: "button.cancel".localized)
        alert.buttons.first?.hasDestructiveAction = true

        if let window = self.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                try? FileManager.default.removeItem(atPath: path)
                self?.refresh()
            }
        } else {
            if alert.runModal() == .alertFirstButtonReturn {
                try? FileManager.default.removeItem(atPath: path)
                refresh()
            }
        }
    }

    // MARK: - 新建/重命名 Alert

    private func presentInlineRename(parentPath: String, isFolder: Bool) {
        let alert = NSAlert()
        alert.messageText = isFolder
            ? "filetree.new_folder.title".localized
            : "filetree.new_file.title".localized
        alert.alertStyle = .informational
        alert.addButton(withTitle: "button.create".localized)
        alert.addButton(withTitle: "button.cancel".localized)

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = isFolder
            ? "filetree.new_folder.placeholder".localized
            : "filetree.new_file.placeholder".localized
        input.stringValue = isFolder ? "New Folder" : "Untitled.txt"
        alert.accessoryView = input

        if let window = self.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                let name = input.stringValue.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let fullPath = (parentPath as NSString).appendingPathComponent(name)
                if isFolder {
                    try? FileManager.default.createDirectory(
                        atPath: fullPath, withIntermediateDirectories: true
                    )
                } else {
                    FileManager.default.createFile(atPath: fullPath, contents: nil)
                }
                self?.refresh()
            }
        } else {
            if alert.runModal() == .alertFirstButtonReturn {
                let name = input.stringValue.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let fullPath = (parentPath as NSString).appendingPathComponent(name)
                if isFolder {
                    try? FileManager.default.createDirectory(
                        atPath: fullPath, withIntermediateDirectories: true
                    )
                } else {
                    FileManager.default.createFile(atPath: fullPath, contents: nil)
                }
                refresh()
            }
        }
    }

    private func presentRenameAlert(currentName: String, parent: String, oldPath: String) {
        let alert = NSAlert()
        alert.messageText = "filetree.rename.title".localized
        alert.alertStyle = .informational
        alert.addButton(withTitle: "filetree.menu.rename".localized)
        alert.addButton(withTitle: "button.cancel".localized)

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = currentName
        alert.accessoryView = input

        if let window = self.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                let newName = input.stringValue.trimmingCharacters(in: .whitespaces)
                guard !newName.isEmpty, newName != currentName else { return }
                let newPath = (parent as NSString).appendingPathComponent(newName)
                try? FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
                self?.refresh()
            }
        } else {
            if alert.runModal() == .alertFirstButtonReturn {
                let newName = input.stringValue.trimmingCharacters(in: .whitespaces)
                guard !newName.isEmpty, newName != currentName else { return }
                let newPath = (parent as NSString).appendingPathComponent(newName)
                try? FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
                refresh()
            }
        }
    }

    private func refresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.store.reload()
            self.outlineView.reloadData()
        }
    }
}

// MARK: - EmphasizedRowView

/// 始终返回 `isEmphasized = true` 的 row view，
/// 使选中行在 NSOutlineView 未获得焦点时也使用蓝色高亮（而非灰色）。
final class EmphasizedRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set { /* 忽略系统设置，始终保持 emphasized 状态 */ }
    }
}
