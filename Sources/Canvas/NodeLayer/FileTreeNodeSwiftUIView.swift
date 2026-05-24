import SwiftUI

// MARK: - 文件树导航状态管理

/// 管理文件树 Finder 式导航的历史栈
@Observable
final class FileTreeNavigationState {
    var currentPath: String
    private(set) var backStack: [String] = []
    private(set) var forwardStack: [String] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    var currentDirectoryName: String {
        URL(fileURLWithPath: currentPath).lastPathComponent
    }

    init(rootPath: String) {
        self.currentPath = rootPath
    }

    func navigateTo(_ path: String) {
        backStack.append(currentPath)
        forwardStack.removeAll()
        currentPath = path
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(currentPath)
        currentPath = previous
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentPath)
        currentPath = next
    }

    func resetToRoot(_ newPath: String) {
        backStack.removeAll()
        forwardStack.removeAll()
        currentPath = newPath
    }
}

// MARK: - 排序方式枚举

enum FileTreeSortOrder {
    case name, modified, size
}

// MARK: - FileTreeNodeSwiftUIView

struct FileTreeNodeSwiftUIView: View {
    let nodeId: UUID
    let content: FileTreeContent
    let isSelected: Bool
    let isLocked: Bool
    let zoom: CGFloat
    let workspace: WorkspaceManager?
    var onActivated: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onDuplicate: ((UUID) -> Void)?
    var onLockToggle: ((UUID, Bool) -> Void)?

    @Environment(\.dropTargetNodeId) private var dropTargetNodeId

    @State private var navState: FileTreeNavigationState
    @State private var viewMode: FileTreeViewMode = .list
    @State private var showGitPanel = false
    @State private var currentBranch: String = ""
    @State private var searchText: String = ""
    @State private var showHiddenFiles: Bool = false
    @State private var sortOrder: FileTreeSortOrder = .name
    @State private var collapseAllTrigger: Int = 0

    private var isDropTarget: Bool { dropTargetNodeId == nodeId }

    init(
        nodeId: UUID,
        content: FileTreeContent,
        isSelected: Bool,
        isLocked: Bool,
        zoom: CGFloat,
        workspace: WorkspaceManager?,
        onActivated: ((UUID) -> Void)? = nil,
        onClose: ((UUID) -> Void)? = nil,
        onRename: ((UUID, String) -> Void)? = nil,
        onDuplicate: ((UUID) -> Void)? = nil,
        onLockToggle: ((UUID, Bool) -> Void)? = nil
    ) {
        self.nodeId = nodeId
        self.content = content
        self.isSelected = isSelected
        self.isLocked = isLocked
        self.zoom = zoom
        self.workspace = workspace
        self.onActivated = onActivated
        self.onClose = onClose
        self.onRename = onRename
        self.onDuplicate = onDuplicate
        self.onLockToggle = onLockToggle
        _navState = State(initialValue: FileTreeNavigationState(rootPath: content.rootPath))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 背景：毛玻璃 + 半透明叠加 + 阴影
            RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                .background {
                    VibrancyBackground(material: .sidebar, blendingMode: .behindWindow)
                        .clipShape(RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius))
                }
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
                .overlay {
                    RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 0.5)
                }

            VStack(spacing: 0) {
                // 顶部导航工具栏
                FileTreeNavigationBar(
                    navState: navState,
                    viewMode: $viewMode,
                    showGitPanel: $showGitPanel,
                    showHiddenFiles: $showHiddenFiles,
                    sortOrder: $sortOrder,
                    currentBranch: currentBranch,
                    isLocked: isLocked,
                    onCollapseAll: {
                        collapseAllTrigger += 1
                    }
                )
                .frame(height: CanvasNodeConstants.headerHeight + 8)

                Divider().opacity(0.3)

                // 文件内容区（根据 viewMode 切换）
                if viewMode == .list {
                    FileTreeRepresentable(
                        nodeId: nodeId,
                        content: content,
                        navState: navState,
                        searchText: searchText,
                        showHiddenFiles: showHiddenFiles,
                        showGitPanel: showGitPanel,
                        collapseAllTrigger: collapseAllTrigger,
                        onBranchLoaded: { branch in currentBranch = branch },
                        onTapped: { onActivated?(nodeId) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    FileTreeGridRepresentable(
                        nodeId: nodeId,
                        navState: navState,
                        onTapped: { onActivated?(nodeId) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Git 操作面板（可折叠）
                if showGitPanel {
                    Divider().opacity(0.3)
                    FileTreeGitPanelView(rootPath: navState.currentPath)
                        .frame(height: 120)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Divider().opacity(0.3)

                // 底部搜索栏
                FileTreeSearchBar(searchText: $searchText)
                    .frame(height: 40)
            }
            .clipShape(RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius))
            .animation(.easeInOut(duration: 0.2), value: showGitPanel)

            // 选中蓝色虚线边框
            if isSelected {
                RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius + CanvasNodeConstants.selectionOutset)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )
                    .foregroundStyle(.blue)
                    .padding(-CanvasNodeConstants.selectionOutset)
                    .allowsHitTesting(false)
            }

            // 拖放目标高亮蓝色实线边框
            if isDropTarget {
                RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius)
                    .strokeBorder(Color.blue.opacity(0.8), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: content.rootPath) { _, newPath in
            if navState.currentPath != newPath {
                navState.resetToRoot(newPath)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NavBarMenuAction.setViewMode)) { note in
            guard (note.userInfo?[NavBarMenuAction.nodeIdKey] as? UUID) == nodeId,
                  let mode = note.userInfo?[NavBarMenuAction.viewModeKey] as? FileTreeViewMode
            else { return }
            viewMode = mode
        }
        .onReceive(NotificationCenter.default.publisher(for: NavBarMenuAction.toggleHidden)) { note in
            guard (note.userInfo?[NavBarMenuAction.nodeIdKey] as? UUID) == nodeId else { return }
            showHiddenFiles.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: NavBarMenuAction.collapseAll)) { note in
            guard (note.userInfo?[NavBarMenuAction.nodeIdKey] as? UUID) == nodeId else { return }
            collapseAllTrigger += 1
        }
    }
}

// MARK: - 顶部导航工具栏

private struct FileTreeNavigationBar: View {
    @Bindable var navState: FileTreeNavigationState
    @Binding var viewMode: FileTreeViewMode
    @Binding var showGitPanel: Bool
    @Binding var showHiddenFiles: Bool
    @Binding var sortOrder: FileTreeSortOrder
    let currentBranch: String
    let isLocked: Bool
    let onCollapseAll: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // ─── 左侧：白色胶囊后退/前进按钮 ───
            HStack(spacing: 0) {
                Button(action: { navState.goBack() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(navState.canGoBack ? Color.primary : Color.secondary.opacity(0.35))
                        .frame(width: 28, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!navState.canGoBack)

                Divider()
                    .frame(height: 14)
                    .opacity(0.4)

                Button(action: { navState.goForward() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(navState.canGoForward ? Color.primary : Color.secondary.opacity(0.35))
                        .frame(width: 28, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!navState.canGoForward)
            }
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            )
            .padding(.leading, 8)

            // ─── 中间：当前目录名称 ───
            Text(navState.currentDirectoryName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(navState.currentPath)

            Spacer()

            // ─── 锁定图标 ───
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // ─── Git Branch 指示器 ───
            if !currentBranch.isEmpty {
                Button(action: { withAnimation { showGitPanel.toggle() } }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                        Text(currentBranch)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundStyle(showGitPanel ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(showGitPanel ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // ─── 右侧：白色胶囊菜单按钮 ───
            Menu {
                // 视图模式
                Button(action: { viewMode = .list }) {
                    Label("列表视图", systemImage: "list.bullet")
                }
                Button(action: { viewMode = .grid }) {
                    Label("图标视图", systemImage: "square.grid.2x2")
                }
                Button(action: {}) {
                    Label("差异视图", systemImage: "arrow.left.arrow.right.square")
                }
                .disabled(true)

                Divider()

                // 显示隐藏文件
                Button(action: { showHiddenFiles.toggle() }) {
                    Label(
                        showHiddenFiles ? "隐藏隐藏文件" : "显示隐藏文件",
                        systemImage: showHiddenFiles ? "eye.slash" : "eye"
                    )
                }

                // 排序方式子菜单
                Menu("排序方式") {
                    Button(action: { sortOrder = .name }) {
                        Label("名称", systemImage: sortOrder == .name ? "checkmark" : "")
                    }
                    Button(action: { sortOrder = .modified }) {
                        Label("修改时间", systemImage: sortOrder == .modified ? "checkmark" : "")
                    }
                    Button(action: { sortOrder = .size }) {
                        Label("大小", systemImage: sortOrder == .size ? "checkmark" : "")
                    }
                }

                Divider()

                // 全部折叠（仅列表模式）
                Button(action: { onCollapseAll() }) {
                    Label("全部折叠", systemImage: "arrow.up.to.line")
                }
                .disabled(viewMode != .list)

            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 12))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.trailing, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Git 操作面板（折叠区域）

private struct FileTreeGitPanelView: View {
    let rootPath: String
    @State private var commitMessage = ""
    @State private var branch = ""

    private var gitProvider: GitStatusProvider {
        GitStatusProvider(workingDirectory: rootPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(branch.isEmpty ? "git.branch.unknown".localized : branch)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            HStack(spacing: 6) {
                TextField("git.commit_message_placeholder", text: $commitMessage)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Button("button.commit") {
                    try? gitProvider.commit(message: commitMessage, files: [])
                    commitMessage = ""
                }
                .disabled(commitMessage.isEmpty)
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 10)

            HStack(spacing: 4) {
                GitActionButton(label: "Pull", icon: "arrow.down") { try? gitProvider.pull() }
                GitActionButton(label: "Push", icon: "arrow.up") { try? gitProvider.push() }
                GitActionButton(label: "Fetch", icon: "arrow.clockwise") { try? gitProvider.fetch() }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .onAppear { branch = (try? gitProvider.currentBranch()) ?? "" }
    }
}

private struct GitActionButton: View {
    let label: String
    let icon: String
    let action: () throws -> Void

    var body: some View {
        Button(action: { try? action() }) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.system(size: 11))
            }
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
    }
}

// MARK: - 底部搜索栏

private struct FileTreeSearchBar: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                TextField("label.search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .quaternarySystemFill))
            )
            .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - NSViewRepresentable 桥接（List 模式）

struct FileTreeRepresentable: NSViewRepresentable {
    let nodeId: UUID
    let content: FileTreeContent
    @Bindable var navState: FileTreeNavigationState
    let searchText: String
    let showHiddenFiles: Bool
    let showGitPanel: Bool
    let collapseAllTrigger: Int
    var onBranchLoaded: ((String) -> Void)?
    var onTapped: (() -> Void)?

    func makeNSView(context: Context) -> NSView {
        if let existing = FileTreeViewRegistry.shared.view(for: nodeId) {
            existing.onNavigateTo = { path in navState.navigateTo(path) }
            existing.onBranchLoaded = onBranchLoaded
            existing.onTapped = onTapped
            return existing
        }

        let fileTreeView = FileTreeOutlineView(rootPath: content.rootPath)
        fileTreeView.onNavigateTo = { path in navState.navigateTo(path) }
        fileTreeView.onBranchLoaded = onBranchLoaded
        fileTreeView.onTapped = onTapped

        FileTreeViewRegistry.shared.register(nodeId: nodeId, view: fileTreeView)
        return fileTreeView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let ftv = nsView as? FileTreeOutlineView else { return }
        if ftv.currentRootPath != navState.currentPath {
            ftv.changeRoot(to: navState.currentPath)
        }
        ftv.onNavigateTo = { path in navState.navigateTo(path) }
        ftv.onBranchLoaded = onBranchLoaded
        ftv.onTapped = onTapped
        ftv.onGoBack = { navState.goBack() }
        ftv.onGoForward = { navState.goForward() }
        ftv.applyFilter(searchText)
        ftv.showHiddenFiles = showHiddenFiles
        // git panel 展开时额外占据 120pt，需告知 fileTreeHitKind 将其识别为 SwiftUI 区域
        ftv.extraBottomSwiftUIHeight = showGitPanel ? 120 : 0

        if context.coordinator.lastCollapseAllTrigger != collapseAllTrigger {
            context.coordinator.lastCollapseAllTrigger = collapseAllTrigger
            ftv.collapseAll()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastCollapseAllTrigger: Int = 0
    }
}

// MARK: - NSViewRepresentable 桥接（Grid 模式）

struct FileTreeGridRepresentable: NSViewRepresentable {
    let nodeId: UUID
    @Bindable var navState: FileTreeNavigationState
    var onTapped: (() -> Void)?

    func makeNSView(context: Context) -> FileTreeIconGridView {
        let grid = FileTreeIconGridView(rootPath: navState.currentPath)
        grid.onNavigateTo = { path in navState.navigateTo(path) }
        grid.onTapped = onTapped
        FileTreeGridViewRegistry.shared.register(nodeId: nodeId, view: grid)
        return grid
    }

    func updateNSView(_ nsView: FileTreeIconGridView, context: Context) {
        if nsView.rootPath != navState.currentPath {
            nsView.changeRoot(to: navState.currentPath)
        }
        nsView.onNavigateTo = { path in navState.navigateTo(path) }
        nsView.onTapped = onTapped
        nsView.onGoBack = { navState.goBack() }
        nsView.onGoForward = { navState.goForward() }
    }
}
