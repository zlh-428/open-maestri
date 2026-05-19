import AppKit
import SwiftUI

// MARK: - 节点画布常量（替代 BaseNodeView 中的静态常量）
enum CanvasNodeConstants {
    static let headerHeight: CGFloat = 32
    static let minNodeWidth: CGFloat = 160
    static let minNodeHeight: CGFloat = 80
    static let resizeHandleSize: CGFloat = 8
    static let cornerRadius: CGFloat = 10
    static let selectionOutset: CGFloat = 8
}

// MARK: - 拖放目标 Environment Key

private struct DropTargetNodeIdKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var dropTargetNodeId: UUID? {
        get { self[DropTargetNodeIdKey.self] }
        set { self[DropTargetNodeIdKey.self] = newValue }
    }
}

// MARK: - CanvasNodesView
/// NSHostingView 子类，作为所有节点的 SwiftUI 容器。
/// hitTest 默认返回 self（不穿透内部 SwiftUI 视图到 AppKit 层），
/// 天然实现 Maestri 的 SwiftUIGestureBlocker 效果。
final class CanvasNodesView: NSHostingView<CanvasNodesSwiftUIView> {
    // 不重写 hitTest：默认行为已满足需求
    // 不重写 mouseDown：由父视图 CanvasViewportView 统一处理
}

// MARK: - CanvasNodesSwiftUIView
/// 所有节点在 ZStack 中以 .frame + .position 布局。
/// 全部设 allowsHitTesting(false)，交互由 AppKit 层统一负责。
struct CanvasNodesSwiftUIView: View {
    let nodes: [CanvasNode]
    let canvasOrigin: CGPoint
    let zoom: CGFloat
    let selectedNodeIds: Set<UUID>
    let lockedNodeIds: Set<UUID>
    let workspace: WorkspaceManager?
    var dropTargetNodeId: UUID? = nil
    var onActivated: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onDuplicate: ((UUID) -> Void)?
    var onLockToggle: ((UUID, Bool) -> Void)?

    var body: some View {
        GeometryReader { _ in
            ZStack {
                ForEach(nodes.sorted(by: { $0.zIndex < $1.zIndex })) { node in
                    nodeView(for: node)
                        .frame(
                            width: node.frame.width * zoom,
                            height: node.frame.height * zoom
                        )
                        .position(
                            x: (node.frame.midX - canvasOrigin.x) * zoom,
                            y: (node.frame.midY - canvasOrigin.y) * zoom
                        )
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.dropTargetNodeId, dropTargetNodeId)
    }

    @ViewBuilder
    private func nodeView(for node: CanvasNode) -> some View {
        let isSelected = selectedNodeIds.contains(node.id)
        let isLocked = lockedNodeIds.contains(node.id)
        switch node.content {
        case .terminal(let tc):
            TerminalNodeSwiftUIView(
                nodeId: node.id, content: tc, isSelected: isSelected, isLocked: isLocked,
                zoom: zoom, workspace: workspace,
                onActivated: onActivated, onClose: onClose,
                onRename: onRename, onDuplicate: onDuplicate, onLockToggle: onLockToggle
            )
        case .stickyNote(let nc):
            NoteNodeSwiftUIView(
                nodeId: node.id, content: nc, isSelected: isSelected, isLocked: isLocked,
                zoom: zoom, workspace: workspace,
                onActivated: onActivated, onClose: onClose,
                onRename: onRename, onDuplicate: onDuplicate, onLockToggle: onLockToggle
            )
        case .portal(let pc):
            PortalNodeSwiftUIView(
                nodeId: node.id, content: pc, isSelected: isSelected, isLocked: isLocked,
                zoom: zoom,
                onActivated: onActivated, onClose: onClose,
                onRename: onRename, onDuplicate: onDuplicate, onLockToggle: onLockToggle
            )
        case .fileTree(let fc):
            FileTreeNodeSwiftUIView(
                nodeId: node.id, content: fc, isSelected: isSelected, isLocked: isLocked,
                zoom: zoom, workspace: workspace,
                onActivated: onActivated, onClose: onClose,
                onRename: onRename, onDuplicate: onDuplicate, onLockToggle: onLockToggle
            )
        case .text(let tc):
            TextNodeSwiftUIView(
                nodeId: node.id, content: tc, isSelected: isSelected, isLocked: isLocked,
                zoom: zoom,
                onActivated: onActivated, onClose: onClose,
                onRename: onRename, onDuplicate: onDuplicate, onLockToggle: onLockToggle
            )
        case .drawing(let dc):
            DrawingNodeSwiftUIView(
                nodeId: node.id, content: dc, isSelected: isSelected, isLocked: isLocked,
                zoom: zoom,
                onActivated: onActivated, onClose: onClose,
                onLockToggle: onLockToggle
            )
        }
    }
}
