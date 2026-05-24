import Foundation
import OSLog

/// 文件树节点（class 保证 NSOutlineView 可用对象身份 === 追踪 item）
final class FileTreeItem: Identifiable, Hashable {
    let id: String   // 绝对路径
    var name: String
    var isDirectory: Bool
    var isExpanded: Bool = false
    var children: [FileTreeItem]?
    var gitStatus: GitFileStatus = .unmodified

    init(id: String, name: String, isDirectory: Bool, isExpanded: Bool = false,
         children: [FileTreeItem]? = nil, gitStatus: GitFileStatus = .unmodified) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.isExpanded = isExpanded
        self.children = children
        self.gitStatus = gitStatus
    }

    static func == (lhs: FileTreeItem, rhs: FileTreeItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Git 文件状态
enum GitFileStatus {
    case unmodified, modified, added, deleted, renamed, untracked
}

/// 文件树状态存储（每个 FileTree 节点独立实例）
@Observable
final class FileTreeStateStore {
    private let logger = Logger.make(category: "FileTreeStateStore")

    var rootPath: String
    var viewMode: FileTreeViewMode = .list
    var items: [FileTreeItem] = []
    var expandedPaths: Set<String> = []
    var gitStatus: [String: GitFileStatus] = [:]

    private var watcher: DirectoryWatcher?
    /// 防抖用的 reload work item
    private var pendingReloadWork: DispatchWorkItem?
    /// 上次 reload 时间戳，避免过于频繁
    private var lastReloadTime: CFAbsoluteTime = 0

    init(rootPath: String) {
        self.rootPath = rootPath
        startWatching()
    }

    deinit { watcher?.stop() }

    private func startWatching() {
        let w = DirectoryWatcher(path: rootPath)
        w.onChange = { [weak self] in
            self?.scheduleReload()
        }
        w.start()
        watcher = w
    }

    /// 防抖 reload：合并 500ms 内的多次文件系统事件
    private func scheduleReload() {
        pendingReloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                await self?.reload()
            }
        }
        pendingReloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: - 加载文件树

    func reload() async {
        // 限流：距离上次 reload 不到 300ms 则跳过
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastReloadTime > 0.3 else { return }
        lastReloadTime = now

        let root = rootPath
        guard FileManager.default.fileExists(atPath: root) else {
            await MainActor.run {
                items = [FileTreeItem(
                    id: root,
                    name: "目录不存在：\(URL(fileURLWithPath: root).lastPathComponent)",
                    isDirectory: false,
                    children: nil
                )]
            }
            return
        }

        // 并行加载文件树（仅加载 1 层，子目录按需展开）和 git 状态
        async let filesTask = Task.detached(priority: .userInitiated) {
            return Self.loadDirectory(path: root, depth: 0, maxDepth: 1)
        }.value
        async let gitTask = Task.detached(priority: .utility) {
            return Self.loadGitStatus(workingDirectory: root)
        }.value

        let (loaded, statusMap) = await (filesTask, gitTask)
        // 将 git 状态标记到文件节点
        let annotated = Self.applyGitStatus(to: loaded, statusMap: statusMap, root: root)
        await MainActor.run {
            items = annotated
            gitStatus = statusMap
        }
    }

    private static func loadGitStatus(workingDirectory: String) -> [String: GitFileStatus] {
        let provider = GitStatusProvider(workingDirectory: workingDirectory)
        guard provider.isGitRepository else { return [:] }
        let statuses = (try? provider.status()) ?? []
        var map: [String: GitFileStatus] = [:]
        for (path, status) in statuses {
            let fullPath = (workingDirectory as NSString).appendingPathComponent(path)
            map[fullPath] = status
        }
        return map
    }

    private static func applyGitStatus(
        to items: [FileTreeItem],
        statusMap: [String: GitFileStatus],
        root: String
    ) -> [FileTreeItem] {
        for item in items {
            if let status = statusMap[item.id] {
                item.gitStatus = status
            }
            if let children = item.children {
                _ = applyGitStatus(to: children, statusMap: statusMap, root: root)
            }
        }
        return items
    }

    private static func loadDirectory(path: String, depth: Int, maxDepth: Int) -> [FileTreeItem] {
        guard depth < maxDepth else { return [] }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: path)
            .filter({ !$0.hasPrefix(".") })
            .sorted() else { return [] }

        let items = entries.compactMap { name -> FileTreeItem? in
            let fullPath = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            return FileTreeItem(
                id: fullPath,
                name: name,
                isDirectory: isDir.boolValue,
                children: nil   // nil 触发 NSOutlineView 占位展开逻辑；展开时异步加载
            )
        }
        // 排序：文件夹在前、文件在后（与 Maestri / Finder 一致）
        return items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }


    // MARK: - 展开/折叠

    func toggle(path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
            Task { await loadChildren(for: path) }
        }
    }

    /// 加载指定路径的子目录，并更新到 items 树中
    func loadChildren(for path: String) async {
        let children = await Task.detached(priority: .userInitiated) {
            return Self.loadDirectory(path: path, depth: 0, maxDepth: 1)
        }.value
        // 应用 git 状态到加载的子节点
        let annotated = Self.applyGitStatus(to: children, statusMap: gitStatus, root: rootPath)
        await MainActor.run {
            updateChildren(annotated, for: path, in: items)
        }
    }

    private func updateChildren(_ children: [FileTreeItem], for path: String, in items: [FileTreeItem]) {
        for item in items {
            if item.id == path {
                item.children = children
                return
            }
            if let existingChildren = item.children {
                updateChildren(children, for: path, in: existingChildren)
            }
        }
    }
}

enum FileTreeViewMode {
    case list, grid
}
