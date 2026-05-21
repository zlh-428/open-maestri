import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    private let outlineView = NSOutlineView()
    private(set) var store: FileTreeStateStore

    /// 暴露 scrollView 引用，供 FileTreeOutlineView 转发滚动事件
    var scrollViewRef: NSScrollView { scrollView }

    /// 防止 reload 时频繁刷新
    private var pendingReloadWorkItem: DispatchWorkItem?

    // MARK: - Callbacks

    /// 双击/单击文件夹时导航进入的回调（传入目录绝对路径）
    var onNavigateTo: ((String) -> Void)?
    /// 双击文件时打开的回调
    var onFileOpened: ((String) -> Void)?
    /// Git 分支加载完成回调
    var onBranchLoaded: ((String) -> Void)?

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
        outlineView.rowHeight = 28
        outlineView.indentationPerLevel = 16
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

    /// 防抖 reload：合并 100ms 内的多次调用
    private func scheduleReload() {
        pendingReloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.outlineView.reloadData()
        }
        pendingReloadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        // Finder 式导航：不展开子树，仅显示当前目录的直接子项
        if item == nil { return store.items.count }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil, index < store.items.count { return store.items[index] }
        return NSNull()
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        // Finder 式导航：文件夹通过双击导航，不在视图内展开
        return false
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let fi = item as? FileTreeItem else { return nil }
        return makeCell(for: fi, in: outlineView)
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return true   // 所有项目均可选中
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return 28
    }

    // MARK: - 单击/双击处理

    /// 单击：仅选中高亮行，不触发任何导航
    @objc private func handleSingleClick() {
        // NSOutlineView 会自动处理选中高亮，无需额外逻辑
        _ = outlineView.clickedRow
    }

    /// 双击处理：
    ///  - 文件夹 → 通过回调导航进入（Finder 式）
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

        configureCellContents(cell, with: fi)
        return cell
    }

    private func buildCellTemplate() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("FileCell")

        // 文件夹展开箭头（对标 Maestri：在图标左侧显示 > 表示可以进入）
        let chevron = NSImageView()
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.identifier = NSUserInterfaceItemIdentifier("chevron")
        chevron.imageScaling = .scaleProportionallyDown
        chevron.contentTintColor = .tertiaryLabelColor
        cell.addSubview(chevron)

        let imgView = NSImageView()
        imgView.translatesAutoresizingMaskIntoConstraints = false
        imgView.imageScaling = .scaleProportionallyDown
        cell.addSubview(imgView)
        cell.imageView = imgView

        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = .systemFont(ofSize: 13)
        textField.lineBreakMode = .byTruncatingTail
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cell.addSubview(textField)
        cell.textField = textField

        NSLayoutConstraint.activate([
            // 左侧展开箭头
            chevron.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            chevron.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10),
            chevron.heightAnchor.constraint(equalToConstant: 10),
            // 文件图标
            imgView.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 6),
            imgView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imgView.widthAnchor.constraint(equalToConstant: 16),
            imgView.heightAnchor.constraint(equalToConstant: 16),
            // 文件名
            textField.leadingAnchor.constraint(equalTo: imgView.trailingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    private func configureCellContents(_ cell: NSTableCellView, with fi: FileTreeItem) {
        cell.textField?.stringValue = fi.name
        cell.imageView?.image = fileIcon(for: fi)

        // 文件夹显示右向箭头，提示可双击进入
        let chevron = cell.subviews.first { $0.identifier?.rawValue == "chevron" } as? NSImageView
        if fi.isDirectory {
            chevron?.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
            chevron?.isHidden = false
        } else {
            chevron?.image = nil
            chevron?.isHidden = true
        }

        // Git 状态颜色
        switch fi.gitStatus {
        case .modified:
            cell.textField?.textColor = .systemOrange
        case .added, .untracked:
            cell.textField?.textColor = .systemGreen
        case .deleted:
            cell.textField?.textColor = .systemRed
        default:
            cell.textField?.textColor = .labelColor
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
