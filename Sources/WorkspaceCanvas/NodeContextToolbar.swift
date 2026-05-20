import SwiftUI

// MARK: - 选中节点浮动工具栏

struct NodeContextToolbar: View {
    let onEdit: () -> Void
    let onConnect: () -> Void
    let onRefresh: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            contextButton(icon: "square.and.pencil", tooltip: "tooltip.node.edit".localized, action: onEdit)
            contextButton(icon: "point.3.connected.trianglepath.dotted", tooltip: "tooltip.node.connect_terminal".localized, action: onConnect)
            contextButton(icon: "arrow.triangle.2.circlepath", tooltip: "tooltip.refresh".localized, action: onRefresh)
            contextButton(icon: "trash", tooltip: "tooltip.node.delete".localized, action: onDelete)
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
            contextButton(icon: "folder.badge.questionmark", tooltip: "tooltip.node.reveal_finder".localized, action: onRevealInFinder)
            contextButton(icon: "folder.badge.gearshape", tooltip: "tooltip.node.change_root".localized, action: onChangeRoot)
            contextButton(icon: "trash", tooltip: "tooltip.node.delete".localized, action: onDelete)
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
