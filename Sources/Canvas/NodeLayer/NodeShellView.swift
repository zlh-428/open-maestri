import SwiftUI
import AppKit

// MARK: - Vibrancy 背景（NSVisualEffectView 桥接）

struct VibrancyBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// 所有节点的通用外壳，替代 BaseNodeView（NSView 子类）。
/// 提供：背景/阴影/圆角、Header 栏、可选 Footer 栏、选中蓝色虚线边框、右键菜单。
struct NodeShellView<Content: View, Accessory: View, Footer: View>: View {
    let nodeId: UUID
    let title: String
    let isSelected: Bool
    let isLocked: Bool
    let isCommunicating: Bool
    let zoom: CGFloat
    let headerIcon: String?
    let headerColor: Color?
    /// Note 节点专用：应用到 header 背景和节点整体背景的主题色。其他节点类型保持 nil。
    let themeColor: Color?
    let headerAccessory: Accessory
    let footer: Footer
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
        isCommunicating: Bool = false,
        zoom: CGFloat,
        headerIcon: String?,
        headerColor: Color?,
        themeColor: Color? = nil,
        @ViewBuilder headerAccessory: () -> Accessory = { EmptyView() },
        @ViewBuilder footer: () -> Footer = { EmptyView() },
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
        self.isCommunicating = isCommunicating
        self.zoom = zoom
        self.headerIcon = headerIcon
        self.headerColor = headerColor
        self.themeColor = themeColor
        self.headerAccessory = headerAccessory()
        self.footer = footer()
        self.onClose = onClose
        self.onRename = onRename
        self.onDuplicate = onDuplicate
        self.onLockToggle = onLockToggle
        self.content = content
    }

    @Environment(\.dropTargetNodeId) private var dropTargetNodeId

    private var isDropTarget: Bool { dropTargetNodeId == nodeId }

    private var hasFooter: Bool { !(Footer.self == EmptyView.self) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 背景：vibrancy 毛玻璃 + 半透明白色叠加 + 阴影
            RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.75))
                .background {
                    VibrancyBackground(material: .popover, blendingMode: .behindWindow)
                        .clipShape(RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius))
                }
                .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
                .overlay {
                    if let themeColor {
                        RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius)
                            .fill(themeColor.opacity(0.05))
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: CanvasNodeConstants.cornerRadius)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
                }

            VStack(spacing: 0) {
                // Header（固定 32pt 高，与 CanvasNodeConstants.headerHeight 对齐）
                NodeHeaderSwiftUIView(
                    title: title,
                    icon: headerIcon,
                    color: headerColor,
                    themeColor: themeColor,
                    isLocked: isLocked,
                    accessory: { headerAccessory }
                )
                .frame(height: CanvasNodeConstants.headerHeight)

                Divider().opacity(0.5)

                // 内容区（以节点原始画布尺寸填满，内容不受 zoom 影响）
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Footer（可选，仅当提供了非 EmptyView 时显示）
                if hasFooter {
                    Divider().opacity(0.3)
                    footer
                        .frame(height: CanvasNodeConstants.footerHeight)
                        .frame(maxWidth: .infinity)
                }
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
    /// Note 节点专用：header 背景叠加颜色（其他节点传 nil 保持原样）
    let themeColor: Color?
    let isLocked: Bool
    let accessory: Accessory

    init(
        title: String,
        icon: String?,
        color: Color?,
        themeColor: Color? = nil,
        isLocked: Bool,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.themeColor = themeColor
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
        .background {
            ZStack {
                VibrancyBackground(material: .sidebar, blendingMode: .behindWindow)
                if let themeColor {
                    themeColor.opacity(0.18)
                }
            }
        }
    }
}

/// 终端节点 Footer 栏（显示当前工作目录）
struct TerminalFooterView: View {
    let directory: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "folder.fill")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(abbreviatedPath)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            VibrancyBackground(material: .sidebar, blendingMode: .behindWindow)
        }
    }

    /// 将绝对路径缩写为 ~/... 形式
    private var abbreviatedPath: String {
        let home = NSHomeDirectory()
        if directory.hasPrefix(home) {
            return "~" + directory.dropFirst(home.count)
        }
        return directory
    }
}
