import SwiftUI
import AppKit

/// 将 CanvasViewportView 包装为 SwiftUI 视图，同时驱动节点渲染引擎
struct CanvasViewportRepresentable: NSViewRepresentable {
    @Binding var canvasOrigin: CGPoint
    @Binding var zoom: CGFloat
    var backgroundMode: String = "dotGrid"
    var workspace: WorkspaceManager?
    var isConnecting: Bool = false
    /// 节点绘制模式（工具栏选中工具后拖拽绘制）
    var isDrawingMode: Bool = false
    var drawingNodeType: String = "terminal"
    var onViewportChanged: ((CGPoint, CGFloat) -> Void)?
    var onDeleteSelectedNodes: (() -> Void)?
    var onNodeJumpNumbersRequested: ((Bool) -> Void)?
    var onConnectionCreated: ((UUID, UUID) -> Void)?
    /// 拖拽绘制完成回调（传入节点类型和画布坐标 CGRect）
    var onNodeDrawn: ((String, CGRect) -> Void)?
    /// 节点选中变化回调（选中 IDs + 首个选中节点的屏幕 frame）
    var onSelectionChanged: ((Set<UUID>, CGRect?) -> Void)?
    /// Finder 文件拖入回调（文件路径数组 + 画布坐标落点）
    var onFilesDropped: (([String], CGPoint) -> Void)?
    /// 文件拖入节点回调（文件路径数组 + 目标节点 ID）
    var onFilesDroppedOnNode: (([String], UUID) -> Void)?
    /// 可用角色预设（用于 TerminalNodeView 右键菜单 Assign Role 子菜单）
    var rolePresets: [RolePreset] = []
    /// Agent 预设列表（供画布空白区域右键菜单 Terminal 子菜单使用）
    var agentPresets: [AgentPreset] = []
    /// 画布空白区域右键菜单：创建节点（nodeType, canvasPoint）
    var onCanvasContextCreateNode: ((String, CGPoint) -> Void)?
    /// 画布空白区域右键菜单：创建终端（presetIndex, canvasPoint）
    var onCanvasContextCreateTerminal: ((Int, CGPoint) -> Void)?
    /// 画布空白区域右键菜单：粘贴（canvasPoint）
    var onCanvasContextPaste: ((CGPoint) -> Void)?

    final class Coordinator {
        var renderer: CanvasNodeRenderer?
        var lastNodeCount: Int = 0
        var lastViewportKey: String = ""  // zoom+origin 变化时触发连线重算
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    func makeNSView(context: Context) -> CanvasViewportView {
        let view = CanvasViewportView()
        view.canvasOrigin = canvasOrigin
        view.zoom = zoom
        view.backgroundMode = backgroundMode
        view.onViewportChanged = onViewportChanged
        view.onDeleteSelectedNodes = onDeleteSelectedNodes
        view.onNodeJumpNumbersRequested = onNodeJumpNumbersRequested
        view.onConnectionCreated = onConnectionCreated
        view.onSelectionChanged = onSelectionChanged
        view.onFilesDropped = onFilesDropped
        view.onFilesDroppedOnNode = onFilesDroppedOnNode
        view.agentPresets = agentPresets
        view.onCanvasContextCreateNode = onCanvasContextCreateNode
        view.onCanvasContextCreateTerminal = onCanvasContextCreateTerminal
        view.onCanvasContextPaste = onCanvasContextPaste

        let renderer = CanvasNodeRenderer(canvas: view)
        context.coordinator.renderer = renderer

        if let ws = workspace {
            renderer.sync(nodes: ws.nodes, workspace: ws)
            renderer.syncConnections(workspace: ws)
        }

        return view
    }

    @MainActor
    func updateNSView(_ nsView: CanvasViewportView, context: Context) {
        let originChanged = nsView.canvasOrigin != canvasOrigin
        let zoomChanged = nsView.zoom != zoom

        if originChanged { nsView.canvasOrigin = canvasOrigin }
        if zoomChanged { nsView.zoom = zoom }
        if nsView.backgroundMode != backgroundMode {
            nsView.backgroundMode = backgroundMode
            nsView.needsDisplay = true
        }

        // 同步连线工具模式
        if nsView.isInConnectingMode != isConnecting {
            nsView.isInConnectingMode = isConnecting
        }

        // 同步节点绘制模式
        nsView.isInDrawingMode = isDrawingMode
        nsView.drawingNodeType = drawingNodeType
        nsView.onNodeDrawn = onNodeDrawn
        nsView.onFilesDropped = onFilesDropped
        nsView.onFilesDroppedOnNode = onFilesDroppedOnNode
        nsView.agentPresets = agentPresets
        nsView.onCanvasContextCreateNode = onCanvasContextCreateNode
        nsView.onCanvasContextCreateTerminal = onCanvasContextCreateTerminal
        nsView.onCanvasContextPaste = onCanvasContextPaste

        guard let ws = workspace, let renderer = context.coordinator.renderer else { return }

        // 同步角色预设到 renderer（供 TerminalNodeView 右键菜单使用）
        renderer.rolePresets = rolePresets

        let nodeCount = ws.nodes.count
        let connCount = ws.connections.count + ws.noteConnections.count + ws.portalConnections.count
            + ws.portalToPortalConnections.count + ws.noteToNoteConnections.count
        let currentHash = nodeCount * 1000 + connCount
        let viewportKey = "\(canvasOrigin.x.rounded())_\(canvasOrigin.y.rounded())_\(zoom)"

        if currentHash != context.coordinator.lastNodeCount {
            // 节点/连接数量变化：完整同步
            renderer.sync(nodes: ws.nodes, workspace: ws)
            renderer.syncConnections(workspace: ws)
            context.coordinator.lastNodeCount = currentHash
            context.coordinator.lastViewportKey = viewportKey
        } else if originChanged || zoomChanged {
            // viewport pan/zoom 变化：轻量级重渲染（只重算屏幕坐标映射，不重算锚点）
            renderer.rerenderConnections()
            context.coordinator.lastViewportKey = viewportKey
        }
    }
}
