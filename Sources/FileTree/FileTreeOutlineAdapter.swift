import AppKit
import SwiftUI

/// 轻量适配器：将 FileTreeListView 包装为 NSView（供 CanvasNodeRenderer 嵌入节点 contentView）
final class FileTreeOutlineView: NSView {
    private var hostingView: NSHostingView<AnyView>?

    init(rootPath: String) {
        super.init(frame: .zero)
        let store = FileTreeStateStore(rootPath: rootPath)
        let view = FileTreeListView(store: .constant(store))
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        hostingView = host
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        hostingView?.frame = bounds
    }
}
