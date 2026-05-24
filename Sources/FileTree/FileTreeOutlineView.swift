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

/// 全局注册表：nodeId → FileTreeIconGridView（供画布路由鼠标事件使用）
final class FileTreeGridViewRegistry {
    static let shared = FileTreeGridViewRegistry()
    private var views: [UUID: FileTreeIconGridView] = [:]
    private let lock = NSLock()
    private init() {}

    func register(nodeId: UUID, view: FileTreeIconGridView) {
        lock.lock(); defer { lock.unlock() }
        views[nodeId] = view
    }

    func unregister(nodeId: UUID) {
        lock.lock(); defer { lock.unlock() }
        views.removeValue(forKey: nodeId)
    }

    func view(for nodeId: UUID) -> FileTreeIconGridView? {
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

    /// SwiftUI 层通过此回调得知用户双击进入了某目录，更新 navState
    var onNavigateTo: ((String) -> Void)?
    /// Git 分支加载完成后的回调
    var onBranchLoaded: ((String) -> Void)?
    /// 任意点击时通知 Canvas 选中此节点
    var onTapped: (() -> Void)? {
        get { outlineNSView?.onTapped }
        set { outlineNSView?.onTapped = newValue }
    }
    /// 后退导航回调（由 CanvasNodesView 在 navBar 区域命中后退按钮时调用）
    var onGoBack: (() -> Void)?
    /// 前进导航回调
    var onGoForward: (() -> Void)?
    /// 节点底部额外的 SwiftUI 区域高度（如 git panel 展开时），供 fileTreeHitKind 识别
    var extraBottomSwiftUIHeight: CGFloat = 0

    /// 是否显示隐藏文件（以 . 开头）
    var showHiddenFiles: Bool {
        get { outlineNSView?.showHiddenFiles ?? false }
        set {
            outlineNSView?.showHiddenFiles = newValue
            outlineNSView?.reloadData()
        }
    }

    /// 当前根路径（供 FileTreeRepresentable.updateNSView 比较使用）
    var currentRootPath: String { store.rootPath }

    init(rootPath: String) {
        self.store = FileTreeStateStore(rootPath: rootPath)
        super.init(frame: .zero)

        let outline = FileTreeOutlineNSView(store: store)
        outline.frame = bounds
        outline.autoresizingMask = [.width, .height]

        // 双击目录 → 通知 navState 导航
        outline.onNavigateTo = { [weak self] path in
            self?.onNavigateTo?(path)
        }
        // 双击文件 → 默认应用打开
        outline.onFileOpened = { path in
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
        // 分支信息加载完成
        outline.onBranchLoaded = { [weak self] branch in
            self?.onBranchLoaded?(branch)
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
            // 刷新分支信息
            self?.outlineNSView?.reloadBranch()
        }
    }

    /// 刷新文件列表
    func refresh() {
        Task { @MainActor [weak self] in
            await self?.store.reload()
            self?.outlineNSView?.reloadData()
        }
    }

    /// 应用搜索过滤词
    func applyFilter(_ query: String) {
        guard outlineNSView?.filterQuery != query else { return }
        outlineNSView?.filterQuery = query
        // 清空搜索时恢复树视图（didSet 已清空 searchResults，这里 reloadData 触发 restoreExpandedPaths）
        if query.isEmpty {
            outlineNSView?.reloadData()
        }
        // 搜索模式：由 didSet → scheduleSearch 异步驱动，无需手动 reloadData
    }

    /// 折叠所有已展开的文件夹
    func collapseAll() {
        outlineNSView?.collapseAll()
    }

    /// 程序化处理点击事件（不依赖 NSEvent 转发）
    /// - Parameters:
    ///   - localPoint: 相对于 FileTreeOutlineView 左上角的坐标
    ///   - clickCount: 1=单击, 2=双击
    func handleClickAtLocalPoint(_ localPoint: NSPoint, clickCount: Int) {
        outlineNSView?.handleClickAtLocalPoint(localPoint, clickCount: clickCount)
    }
}
