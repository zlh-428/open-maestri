import AppKit

/// 全局注册表：nodeId → FileTreeOutlineView（供画布路由滚动事件使用）
final class FileTreeViewRegistry {
    static let shared = FileTreeViewRegistry()
    private var views: [UUID: FileTreeOutlineView] = [:]
    private let lock = NSLock()
    private init() {}

    func register(nodeId: UUID, view: FileTreeOutlineView) {
        lock.lock(); defer { lock.unlock() }
        views[nodeId] = view
    }

    func unregister(nodeId: UUID) {
        lock.lock(); defer { lock.unlock() }
        views.removeValue(forKey: nodeId)
    }

    func view(for nodeId: UUID) -> FileTreeOutlineView? {
        lock.lock(); defer { lock.unlock() }
        return views[nodeId]
    }
}

/// 轻量适配器：将 FileTreeOutlineNSView 包装为 NSView（供 CanvasNodeRenderer 嵌入节点 contentView）
final class FileTreeOutlineView: NSView {
    private var outlineNSView: FileTreeOutlineNSView?
    private(set) var store: FileTreeStateStore

    /// 内部 NSScrollView（供外部路由滚动事件使用）
    var innerScrollView: NSScrollView? { outlineNSView?.scrollViewRef }

    /// 单击文件夹时的回调（Finder 式导航：传入目标文件夹路径）
    var onDirectoryClicked: ((String) -> Void)?
    /// 单击文件时的回调
    var onFileClicked: ((String) -> Void)?

    init(rootPath: String) {
        self.store = FileTreeStateStore(rootPath: rootPath)
        super.init(frame: .zero)

        let outline = FileTreeOutlineNSView(store: store)
        outline.frame = bounds
        outline.autoresizingMask = [.width, .height]
        outline.onDirectoryClicked = { [weak self] path in
            self?.onDirectoryClicked?(path)
        }
        outline.onFileClicked = { [weak self] path in
            self?.onFileClicked?(path)
        }
        addSubview(outline)
        outlineNSView = outline
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        outlineNSView?.frame = bounds
    }

    /// 更换根目录（切换到新路径并刷新列表）
    func changeRoot(to newPath: String) {
        store = FileTreeStateStore(rootPath: newPath)
        outlineNSView?.updateStore(store)
        Task { @MainActor [weak self] in
            await self?.store.reload()
            self?.outlineNSView?.reloadData()
        }
    }

    /// 刷新文件列表
    func refresh() {
        Task { @MainActor [weak self] in
            await self?.store.reload()
            self?.outlineNSView?.reloadData()
        }
    }
}
