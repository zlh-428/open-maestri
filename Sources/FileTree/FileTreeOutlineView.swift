import AppKit
import SwiftUI

/// File Tree List View（NSOutlineView 包装）
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

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
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
    }
}
