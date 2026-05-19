import AppKit
import SwiftUI

// MARK: - 节点画布常量（替代 BaseNodeView 中的静态常量）
enum CanvasNodeConstants {
    static let headerHeight: CGFloat = 32
    static let minNodeWidth: CGFloat = 160
    static let minNodeHeight: CGFloat = 80
    static let resizeHandleSize: CGFloat = 12
    static let cornerRadius: CGFloat = 10
    static let selectionOutset: CGFloat = 3
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
/// 所有鼠标/滚轮事件透传给父视图 CanvasViewportView 统一处理。
final class CanvasNodesView: NSHostingView<CanvasNodesSwiftUIView> {


    override func mouseDown(with event: NSEvent) {
        nextResponder?.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        nextResponder?.mouseUp(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        nextResponder?.mouseDragged(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        nextResponder?.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        nextResponder?.rightMouseUp(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        nextResponder?.mouseMoved(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
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
                    let posX = (node.frame.midX - canvasOrigin.x) * zoom
                    let posY = (node.frame.midY - canvasOrigin.y) * zoom
                    nodeView(for: node)
                        // 以原始画布尺寸渲染，内容不感知 zoom
                        .frame(width: node.frame.width, height: node.frame.height)
                        // scaleEffect 从中心缩放到屏幕尺寸，与 position center 语义匹配
                        .scaleEffect(zoom)
                        // position 与 hitTestCanvas/canvasRectToScreen 坐标系完全一致
                        .position(x: posX, y: posY)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // 忽略 safe area，使 GeometryReader 尺寸与 NSHostingView frame 完全一致
        // 否则 safe area insets 导致 SwiftUI .position() 坐标与 AppKit hitTest 坐标系不对齐
        .ignoresSafeArea()
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
                zoom: zoom, nodeSize: node.frame.size, workspace: workspace,
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
