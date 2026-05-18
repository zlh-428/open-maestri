import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File Tree List View（NSOutlineView 包装）
/// Finder 式导航：单击文件夹通过回调通知外部"导航进入"，不在本视图内展开子树
final class FileTreeOutlineNSView: NSView, NSOutlineViewDelegate, NSOutlineViewDataSource {
    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private(set) var store: FileTreeStateStore
    /// 防止 reload 时频繁刷新
    private var pendingReloadWorkItem: DispatchWorkItem?

    /// 单击文件夹时的回调：传入文件夹的绝对路径
    var onDirectoryClicked: ((String) -> Void)?
    /// 单击文件时的回调
    var onFileClicked: ((String) -> Void)?

    init(store: FileTreeStateStore) {
        self.store = store
        super.init(frame: .zero)
        setupViews()
        // 首次加载数据
        Task { @MainActor [weak self] in
            await store.reload()
            self?.outlineView.reloadData()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupViews() {
        let col = NSTableColumn(identifier: .init("name"))
        col.title = "名称"
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col
        outlineView.headerView = nil
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 14
        outlineView.selectionHighlightStyle = .regular
        outlineView.style = .sourceList
        outlineView.target = self
        outlineView.action = #selector(handleSingleClick)
        outlineView.doubleAction = #selector(handleDoubleClick)

        // 拖拽支持
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)

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

    // MARK: - 外部刷新（带防抖）

    func reloadData() {
        scheduleReload()
    }

    func updateStore(_ newStore: FileTreeStateStore) {
        store = newStore
        scheduleReload()
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
        if item == nil { return store.items[index] }
        return NSNull()
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        // Finder 式：不提供展开功能，文件夹通过点击导航
        return false
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let fi = item as? FileTreeItem else { return nil }

        let cellId = NSUserInterfaceItemIdentifier("FileCell")
        let cell: NSTableCellView
        if let existing = outlineView.makeView(withIdentifier: cellId, owner: self) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = cellId

            let imgView = NSImageView()
            imgView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imgView)
            cell.imageView = imgView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = .systemFont(ofSize: 13)
            textField.lineBreakMode = .byTruncatingTail
            cell.addSubview(textField)
            cell.textField = textField

            // 文件夹展开箭头指示器
            let chevron = NSImageView()
            chevron.translatesAutoresizingMaskIntoConstraints = false
            chevron.identifier = NSUserInterfaceItemIdentifier("chevron")
            chevron.imageScaling = .scaleProportionallyDown
            chevron.contentTintColor = .tertiaryLabelColor
            cell.addSubview(chevron)

            NSLayoutConstraint.activate([
                imgView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imgView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imgView.widthAnchor.constraint(equalToConstant: 16),
                imgView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imgView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                chevron.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                chevron.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                chevron.widthAnchor.constraint(equalToConstant: 10),
                chevron.heightAnchor.constraint(equalToConstant: 10),
            ])
        }

        cell.textField?.stringValue = fi.name
        cell.imageView?.image = fileIcon(for: fi)

        // 文件夹显示展开箭头 ">"
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

        return cell
    }

    /// 允许选中任何项
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return true
    }

    // MARK: - 单击/双击

    /// 单击：文件夹则导航进入
    @objc private func handleSingleClick() {
        let row = outlineView.clickedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? FileTreeItem else { return }
        if item.isDirectory {
            onDirectoryClicked?(item.id)
        } else {
            onFileClicked?(item.id)
        }
    }

    /// 双击：文件用默认应用打开
    @objc private func handleDoubleClick() {
        let row = outlineView.clickedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? FileTreeItem else { return }
        if !item.isDirectory {
            NSWorkspace.shared.open(URL(fileURLWithPath: item.id))
        } else {
            // 双击文件夹也是导航进入
            onDirectoryClicked?(item.id)
        }
    }

    // MARK: - 拖拽

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let fi = item as? FileTreeItem else { return nil }
        return URL(fileURLWithPath: fi.id) as NSURL
    }

    // MARK: - 辅助

    private func fileIcon(for item: FileTreeItem) -> NSImage {
        if item.isDirectory {
            return NSWorkspace.shared.icon(for: UTType.folder)
        }
        let url = URL(fileURLWithPath: item.id)
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
