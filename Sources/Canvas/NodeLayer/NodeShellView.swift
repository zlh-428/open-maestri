import SwiftUI

/// 所有节点的通用外壳，替代 BaseNodeView（NSView 子类）。
/// 提供：背景/阴影/圆角、Header 栏、选中蓝色虚线边框、右键菜单。
struct NodeShellView<Content: View>: View {
    let nodeId: UUID
    let title: String
    let isSelected: Bool
    let isLocked: Bool
    let zoom: CGFloat
    let headerIcon: String?
    let headerColor: Color?
    var onClose: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onDuplicate: (() -> Void)?
    var onLockToggle: ((Bool) -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 背景
            RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                .overlay {
                    RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius)
                        .stroke(Color(white: 0.85), lineWidth: 0.5)
                }

            VStack(spacing: 0) {
                // Header
                NodeHeaderSwiftUIView(
                    title: title,
                    icon: headerIcon,
                    color: headerColor,
                    isLocked: isLocked,
                    zoom: zoom
                )
                .frame(height: CanvasNodeConstants.headerHeight / zoom)

                Divider().opacity(0.5)

                // 内容区
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
        .contextMenu {
            if let onRename {
                Button("Rename") { onRename(title) }
            }
            if let onDuplicate {
                Button("Duplicate") { onDuplicate() }
            }
            if let onLockToggle {
                Button(isLocked ? "Unlock" : "Lock") { onLockToggle(!isLocked) }
            }
            Divider()
            if let onClose {
                Button(role: .destructive) { onClose() } label: { Text("Close") }
            }
        }
    }
}

/// Header 栏（标题 + 图标 + 锁定徽章）
struct NodeHeaderSwiftUIView: View {
    let title: String
    let icon: String?
    let color: Color?
    let isLocked: Bool
    let zoom: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11 / zoom))
                    .foregroundStyle(color ?? .primary)
            }
            Text(title)
                .font(.system(size: 12 / zoom, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10 / zoom))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8 / zoom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color?.opacity(0.15) ?? Color.clear)
    }
}
