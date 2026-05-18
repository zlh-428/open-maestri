import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File Tree List View（NSOutlineView 包装）
/// 支持拖拽文件到画布（Terminal 节点或空白区域）
struct FileTreeListView: NSViewRepresentable {
    @Binding var store: FileTreeStateStore

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        let col = NSTableColumn(identifier: .init("name"))
        col.title = "名称"
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.delegate = context.coordinator
        outline.dataSource = context.coordinator

        // 注册拖拽类型（文件 URL）
        outline.setDraggingSourceOperationMask(.copy, forLocal: true)
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.store = store
        (nsView.documentView as? NSOutlineView)?.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    final class Coordinator: NSObject, NSOutlineViewDelegate, NSOutlineViewDataSource {
        var store: FileTreeStateStore
        init(store: FileTreeStateStore) { self.store = store }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil { return store.items.count }
            if let fi = item as? FileTreeItem { return fi.children?.count ?? 0 }
            return 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil { return store.items[index] }
            if let fi = item as? FileTreeItem, let children = fi.children { return children[index] }
            return NSNull()
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? FileTreeItem)?.isDirectory ?? false
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let fi = item as? FileTreeItem else { return nil }
            let cell = NSTextField(labelWithString: fi.name)
            cell.font = .systemFont(ofSize: 12)
            return cell
        }

        // MARK: - 拖拽源支持

        /// 允许拖拽写入 pasteboard
        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let fi = item as? FileTreeItem else { return nil }
            let url = URL(fileURLWithPath: fi.id) as NSURL
            return url
        }

        /// 拖拽会话开始
        func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                         willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
            session.animatesToStartingPositionsOnCancelOrFail = true
        }
    }
}
