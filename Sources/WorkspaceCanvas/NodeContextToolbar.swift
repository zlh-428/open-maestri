import SwiftUI

// MARK: - 连接信息（工具栏传递用）

struct ToolbarConnectionItem: Identifiable {
    let id: UUID
    let peerName: String
    let peerIcon: String
}

// MARK: - 选中节点浮动工具栏

struct NodeContextToolbar: View {
    let onEdit: () -> Void
    let onConnect: () -> Void
    let onRefresh: () -> Void
    let onDelete: () -> Void
    var connections: [ToolbarConnectionItem] = []
    var onDeleteConnection: (UUID) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 2) {
            contextButton(icon: "square.and.pencil", tooltip: "tooltip.node.edit".localized, action: onEdit)
            contextButton(icon: "arrow.trianglehead.branch", tooltip: "tooltip.node.connect_terminal".localized, action: onConnect)
            if !connections.isEmpty {
                ConnectionBadgeButton(connections: connections, onDelete: onDeleteConnection)
            }
            contextButton(icon: "arrow.triangle.2.circlepath", tooltip: "tooltip.refresh".localized, action: onRefresh)
            contextButton(icon: "trash", tooltip: "tooltip.node.delete".localized, action: onDelete)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(white: 0.9), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func contextButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        ContextToolbarButton(icon: icon, tooltip: tooltip, action: action)
    }
}

// MARK: - 连接数量徽章按钮

struct ConnectionBadgeButton: View {
    let connections: [ToolbarConnectionItem]
    let onDelete: (UUID) -> Void

    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 20, height: 20)
                Text("\(connections.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("tooltip.node.connections".localized)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ConnectionListPopover(
                connections: connections,
                onDelete: { id in
                    onDelete(id)
                    if connections.count <= 1 { showPopover = false }
                }
            )
        }
    }
}

// MARK: - 连接列表 Popover

struct ConnectionListPopover: View {
    let connections: [ToolbarConnectionItem]
    let onDelete: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("toolbar.connections.title".localized)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(white: 0.2))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            VStack(spacing: 0) {
                ForEach(connections) { item in
                    ConnectionRow(item: item, onDelete: onDelete)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minWidth: 200)
    }
}

// MARK: - 连接列表行

private struct ConnectionRow: View {
    let item: ToolbarConnectionItem
    let onDelete: (UUID) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.peerIcon)
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.5))
                .frame(width: 16)

            Text(item.peerName)
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.2))
                .lineLimit(1)

            Spacer()

            Button {
                onDelete(item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(white: isHovered ? 0.4 : 0.65))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
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
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(white: 0.9), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func contextButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        ContextToolbarButton(icon: icon, tooltip: tooltip, action: action)
    }
}
