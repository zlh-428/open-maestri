import SwiftUI

// MARK: - 选中节点浮动工具栏

struct NodeContextToolbar: View {
    let onEdit: () -> Void
    let onConnect: () -> Void
    let onRefresh: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            contextButton(icon: "square.and.pencil", tooltip: "编辑", action: onEdit)
            contextButton(icon: "point.3.connected.trianglepath.dotted", tooltip: "连接到终端", action: onConnect)
            contextButton(icon: "arrow.triangle.2.circlepath", tooltip: "刷新", action: onRefresh)
            contextButton(icon: "trash", tooltip: "删除", action: onDelete)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            Capsule()
                .fill(.white)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .overlay(
                    Capsule()
                        .strokeBorder(Color(white: 0.9), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private func contextButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        ContextToolbarButton(icon: icon, tooltip: tooltip, action: action)
    }
}

// MARK: - FileTree 选中节点浮动工具栏

struct FileTreeContextToolbar: View {
    let onRevealInFinder: () -> Void
    let onChangeRoot: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            contextButton(icon: "folder.badge.questionmark", tooltip: "在访达中显示", action: onRevealInFinder)
            contextButton(icon: "folder.badge.gearshape", tooltip: "更改根目录", action: onChangeRoot)
            contextButton(icon: "trash", tooltip: "删除", action: onDelete)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            Capsule()
                .fill(.white)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .overlay(
                    Capsule()
                        .strokeBorder(Color(white: 0.9), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private func contextButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        ContextToolbarButton(icon: icon, tooltip: tooltip, action: action)
    }
}
