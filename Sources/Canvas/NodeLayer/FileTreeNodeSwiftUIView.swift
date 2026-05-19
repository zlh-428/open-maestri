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

    private var isDropTarget: Bool { dropTargetNodeId == nodeId }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 背景
            RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                .overlay {
                    RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius)
                        .stroke(Color(white: 0.85), lineWidth: 0.5)
                }

            VStack(spacing: 0) {
                // 自定义导航栏 Header
                FileTreeNavigationBar(
                    rootPath: content.rootPath,
                    isLocked: isLocked
                )
                .frame(height: CanvasNodeConstants.headerHeight + 8)

                Divider().opacity(0.3)

                // 文件列表内容区
                FileTreeRepresentable(nodeId: nodeId, content: content, workspace: workspace)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().opacity(0.3)

                // 底部搜索栏
                FileTreeSearchBar()
                    .frame(height: 40)
            }
            .clipShape(RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius))

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
        .contextMenu {
            if let onRename {
                Button("Rename") { onRename(nodeId, content.name) }
            }
            if let onDuplicate {
                Button("Duplicate") { onDuplicate(nodeId) }
            }
            if let onLockToggle {
                Button(isLocked ? "Unlock" : "Lock") { onLockToggle(nodeId, !isLocked) }
            }
            Divider()
            if let onClose {
                Button(role: .destructive) { onClose(nodeId) } label: { Text("Close") }
            }
        }
    }
}

// MARK: - 导航栏（对标 Maestri 文件树 Header）

private struct FileTreeNavigationBar: View {
    let rootPath: String
    let isLocked: Bool

    private var directoryName: String {
        URL(fileURLWithPath: rootPath).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 0) {
            // 后退/前进按钮组
            HStack(spacing: 0) {
                Button(action: {}) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {}) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 8)

            // 目录名称
            Text(directoryName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 4)

            Spacer()

            // 锁定图标
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
            }

            // 排序/视图模式按钮
            Button(action: {}) {
                HStack(spacing: 2) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                }
                .foregroundStyle(.primary)
                .frame(width: 36, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                Text("搜索")
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

// MARK: - NSViewRepresentable 桥接

struct FileTreeRepresentable: NSViewRepresentable {
    let nodeId: UUID
    let content: FileTreeContent
    let workspace: WorkspaceManager?

    func makeNSView(context: Context) -> NSView {
        // 复用已注册的 view（避免切换工作区时重建）
        if let existing = FileTreeViewRegistry.shared.view(for: nodeId) {
            return existing
        }

        let fileTreeView = FileTreeOutlineView(rootPath: content.rootPath)
        // 设置导航回调：双击文件夹 → 更新根路径
        fileTreeView.onDirectoryClicked = { [weak fileTreeView] dirPath in
            fileTreeView?.changeRoot(to: dirPath)
        }
        // 注册到全局 registry，供画布路由滚动事件
        FileTreeViewRegistry.shared.register(nodeId: nodeId, view: fileTreeView)
        return fileTreeView
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
