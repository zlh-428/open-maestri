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

    /// 每个节点独立的导航状态（State 保证生命周期绑定到视图）
    @State private var navState: FileTreeNavigationState
    @State private var viewMode: FileTreeViewMode = .list
    @State private var showGitPanel = false
    @State private var currentBranch: String = ""

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
            // 背景：vibrancy 毛玻璃 + 半透明叠加 + 阴影
            RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.75))
                .background {
                    VibrancyBackground(material: .popover, blendingMode: .behindWindow)
                        .clipShape(RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius))
                }
                .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
                .overlay {
                    RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
                }

            VStack(spacing: 0) {
                // 对标 Maestri 的 Header 工具栏
                FileTreeNavigationBar(
                    navState: navState,
                    viewMode: $viewMode,
                    showGitPanel: $showGitPanel,
                    currentBranch: currentBranch,
                    isLocked: isLocked,
                    rootPath: content.rootPath
                )
                .frame(height: CanvasNodeConstants.headerHeight + 8)

                Divider().opacity(0.3)

                // 文件内容区（根据 viewMode 切换）
                if viewMode == .list {
                    FileTreeRepresentable(
                        nodeId: nodeId,
                        content: content,
                        navState: navState,
                        onBranchLoaded: { branch in
                            currentBranch = branch
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    FileTreeGridRepresentable(
                        nodeId: nodeId,
                        navState: navState
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
                FileTreeSearchBar()
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
        // 右键菜单由 AppKit 层 CanvasViewportView.menu(for:) 统一处理
    }
}

// MARK: - 顶部导航工具栏（对标 Maestri [<][>] 路径 [List|Grid] [Branch]）

private struct FileTreeNavigationBar: View {
    @Bindable var navState: FileTreeNavigationState
    @Binding var viewMode: FileTreeViewMode
    @Binding var showGitPanel: Bool
    let currentBranch: String
    let isLocked: Bool
    let rootPath: String

    var body: some View {
        HStack(spacing: 0) {
            // ─── 后退 / 前进 按钮 ───
            HStack(spacing: 0) {
                Button(action: { navState.goBack() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(navState.canGoBack ? Color.primary : Color.secondary.opacity(0.4))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!navState.canGoBack)

                Button(action: { navState.goForward() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(navState.canGoForward ? Color.primary : Color.secondary.opacity(0.4))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!navState.canGoForward)
            }
            .padding(.leading, 8)

            // ─── 当前目录名称（截断显示） ───
            Text(navState.currentDirectoryName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 4)
                .help(navState.currentPath)   // hover tooltip 显示完整路径

            Spacer()

            // ─── 锁定图标 ───
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
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
                .padding(.trailing, 4)
            }

            // ─── List / Grid 视图切换 ───
            HStack(spacing: 1) {
                Button(action: { viewMode = .list }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12))
                        .foregroundStyle(viewMode == .list ? Color.accentColor : Color.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(viewMode == .list ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: { viewMode = .grid }) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12))
                        .foregroundStyle(viewMode == .grid ? Color.accentColor : Color.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(viewMode == .grid ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
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
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Text("label.search")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .placeholderTextColor))

                Spacer()
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
    var onBranchLoaded: ((String) -> Void)?

    func makeNSView(context: Context) -> NSView {
        // 复用已注册的 view（避免切换工作区时重建）
        if let existing = FileTreeViewRegistry.shared.view(for: nodeId) {
            // 将最新的 navState 回调注入到已有 view
            existing.onNavigateTo = { path in
                navState.navigateTo(path)
            }
            existing.onBranchLoaded = onBranchLoaded
            return existing
        }

        let fileTreeView = FileTreeOutlineView(rootPath: content.rootPath)
        fileTreeView.onNavigateTo = { path in
            navState.navigateTo(path)
        }
        fileTreeView.onBranchLoaded = onBranchLoaded

        FileTreeViewRegistry.shared.register(nodeId: nodeId, view: fileTreeView)
        return fileTreeView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let ftv = nsView as? FileTreeOutlineView else { return }
        // navState.currentPath 变化时，更新 outline view 的根目录
        if ftv.currentRootPath != navState.currentPath {
            ftv.changeRoot(to: navState.currentPath)
        }
        // 保证回调始终是最新的
        ftv.onNavigateTo = { path in
            navState.navigateTo(path)
        }
        ftv.onBranchLoaded = onBranchLoaded
    }
}

// MARK: - NSViewRepresentable 桥接（Grid 模式）

struct FileTreeGridRepresentable: NSViewRepresentable {
    let nodeId: UUID
    @Bindable var navState: FileTreeNavigationState

    func makeNSView(context: Context) -> FileTreeIconGridView {
        let grid = FileTreeIconGridView(rootPath: navState.currentPath)
        grid.onNavigateTo = { path in
            navState.navigateTo(path)
        }
        return grid
    }

    func updateNSView(_ nsView: FileTreeIconGridView, context: Context) {
        if nsView.rootPath != navState.currentPath {
            nsView.changeRoot(to: navState.currentPath)
        }
        nsView.onNavigateTo = { path in
            navState.navigateTo(path)
        }
    }
}
