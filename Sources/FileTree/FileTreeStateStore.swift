import Foundation
import OSLog

/// 文件树节点
struct FileTreeItem: Identifiable, Hashable {
    let id: String   // 绝对路径
    var name: String
    var isDirectory: Bool
    var isExpanded: Bool = false
    var children: [FileTreeItem]?
    var gitStatus: GitFileStatus = .unmodified
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

    init(rootPath: String) {
        self.rootPath = rootPath
        startWatching()
    }

    deinit { watcher?.stop() }

    private func startWatching() {
        let w = DirectoryWatcher(path: rootPath)
        w.onChange = { [weak self] in
            Task { await self?.reload() }
        }
        w.start()
        watcher = w
    }

    // MARK: - 加载文件树

    func reload() async {
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

        // 并行加载文件树和 git 状态
        async let filesTask = Task.detached(priority: .userInitiated) {
            return Self.loadDirectory(path: root, depth: 0, maxDepth: 3)
        }.value
        async let gitTask = Task.detached(priority: .utility) {
            return Self.loadGitStatus(workingDirectory: root)
        }.value

        let (loaded, statusMap) = await (filesTask, gitTask)
        // 将 git 状态标记到文件节点
        let annotated = Self.applyGitStatus(to: loaded, statusMap: statusMap, root: root)
        items = annotated
        gitStatus = statusMap
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
        items.map { item in
            var mutable = item
            if let status = statusMap[item.id] {
                mutable.gitStatus = status
            }
            if let children = item.children {
                mutable.children = applyGitStatus(to: children, statusMap: statusMap, root: root)
            }
            return mutable
        }
    }

    private static func loadDirectory(path: String, depth: Int, maxDepth: Int) -> [FileTreeItem] {
        guard depth < maxDepth else { return [] }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: path)
            .filter({ !$0.hasPrefix(".") })
            .sorted() else { return [] }

        return entries.compactMap { name -> FileTreeItem? in
            let fullPath = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            return FileTreeItem(
                id: fullPath,
                name: name,
                isDirectory: isDir.boolValue,
                children: isDir.boolValue ? [] : nil
            )
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

    private func loadChildren(for path: String) async {
        let children = await Task.detached(priority: .userInitiated) {
            return Self.loadDirectory(path: path, depth: 0, maxDepth: 1)
        }.value
        updateChildren(children, for: path, in: &items)
    }

    private func updateChildren(_ children: [FileTreeItem], for path: String, in items: inout [FileTreeItem]) {
        for i in items.indices {
            if items[i].id == path {
                items[i].children = children
                return
            }
            if var children_ = items[i].children {
                updateChildren(children, for: path, in: &children_)
                items[i].children = children_
            }
        }
    }
}

enum FileTreeViewMode {
    case list, grid
}
