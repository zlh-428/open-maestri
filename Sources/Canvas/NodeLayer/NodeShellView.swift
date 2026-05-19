import SwiftUI

/// 所有节点的通用外壳，替代 BaseNodeView（NSView 子类）。
/// 提供：背景/阴影/圆角、Header 栏、选中蓝色虚线边框、右键菜单。
struct NodeShellView<Content: View, Accessory: View>: View {
    let nodeId: UUID
    let title: String
    let isSelected: Bool
    let isLocked: Bool
    let zoom: CGFloat
    let headerIcon: String?
    let headerColor: Color?
    let headerAccessory: Accessory
    var onClose: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onDuplicate: (() -> Void)?
    var onLockToggle: ((Bool) -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        nodeId: UUID,
        title: String,
        isSelected: Bool,
        isLocked: Bool,
        zoom: CGFloat,
        headerIcon: String?,
        headerColor: Color?,
        @ViewBuilder headerAccessory: () -> Accessory = { EmptyView() },
        onClose: (() -> Void)? = nil,
        onRename: ((String) -> Void)? = nil,
        onDuplicate: (() -> Void)? = nil,
        onLockToggle: ((Bool) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.nodeId = nodeId
        self.title = title
        self.isSelected = isSelected
        self.isLocked = isLocked
        self.zoom = zoom
        self.headerIcon = headerIcon
        self.headerColor = headerColor
        self.headerAccessory = headerAccessory()
        self.onClose = onClose
        self.onRename = onRename
        self.onDuplicate = onDuplicate
        self.onLockToggle = onLockToggle
        self.content = content
    }

    @Environment(\.dropTargetNodeId) private var dropTargetNodeId

    private var isDropTarget: Bool { dropTargetNodeId == nodeId }

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
                // Header（固定 32pt 高，与 CanvasNodeConstants.headerHeight 对齐）
                NodeHeaderSwiftUIView(
                    title: title,
                    icon: headerIcon,
                    color: headerColor,
                    isLocked: isLocked,
                    accessory: { headerAccessory }
                )
                .frame(height: CanvasNodeConstants.headerHeight)

                Divider().opacity(0.5)

                // 内容区（以节点原始画布尺寸填满，内容不受 zoom 影响）
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

            // 拖放目标高亮蓝色实线边框
            if isDropTarget {
                RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius)
                    .strokeBorder(Color.blue.opacity(0.8), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        // 右键菜单由 AppKit 层 CanvasViewportView.menu(for:) 统一处理
        // （SwiftUI .contextMenu 因 allowsHitTesting(false) 永远不会触发）
    }
}

/// Header 栏（标题 + 图标 + 锁定徽章 + 可选配件）
struct NodeHeaderSwiftUIView<Accessory: View>: View {
    let title: String
    let icon: String?
    let color: Color?
    let isLocked: Bool
    let accessory: Accessory

    init(
        title: String,
        icon: String?,
        color: Color?,
        isLocked: Bool,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.isLocked = isLocked
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(color ?? .primary)
            }
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            accessory
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color?.opacity(0.15) ?? Color.clear)
    }
}
