import Foundation

// MARK: - Notification Names

extension Notification.Name {
    static let showCreateWorkspace = Notification.Name("OpenMaestri.showCreateWorkspace")
    static let toggleCanvasZoom    = Notification.Name("OpenMaestri.toggleCanvasZoom")
    static let showFloorOverview   = Notification.Name("OpenMaestri.showFloorOverview")
    static let showCanvasFilter    = Notification.Name("OpenMaestri.showCanvasFilter")
    static let openInEditor        = Notification.Name("OpenMaestri.openInEditor")
    static let nextWorkspace       = Notification.Name("OpenMaestri.nextWorkspace")
    static let prevWorkspace       = Notification.Name("OpenMaestri.prevWorkspace")
    static let nextTerminal        = Notification.Name("OpenMaestri.nextTerminal")
    static let prevTerminal        = Notification.Name("OpenMaestri.prevTerminal")
    static let canvasZoomIn        = Notification.Name("OpenMaestri.canvasZoomIn")
    static let canvasZoomOut       = Notification.Name("OpenMaestri.canvasZoomOut")
    static let canvasZoomReset     = Notification.Name("OpenMaestri.canvasZoomReset")
    /// Minimap 点击跳转：userInfo 含 "origin" CGPoint（画布坐标）
    static let canvasJumpToOrigin  = Notification.Name("OpenMaestri.canvasJumpToOrigin")
    /// Maestro recruit 完成通知
    static let maestroRecruited        = Notification.Name("OpenMaestri.maestroRecruited")
    /// 编辑终端请求：userInfo 含 nodeId/terminalContent
    static let editTerminalRequested   = Notification.Name("OpenMaestri.editTerminalRequested")
    /// 右键菜单：开始连接（userInfo 含 "nodeId" UUID）
    static let contextMenuConnect      = Notification.Name("OpenMaestri.contextMenuConnect")
    /// 右键菜单：分配角色（userInfo 含 "nodeId" UUID）
    static let contextMenuAssignRole   = Notification.Name("OpenMaestri.contextMenuAssignRole")
    /// 右键菜单：切换 Maestro 模式（userInfo 含 "nodeId" UUID）
    static let contextMenuToggleMaestro = Notification.Name("OpenMaestri.contextMenuToggleMaestro")
    /// Portal WebView 重建通知（shareSession 后更新视图）
    static let portalWebViewReplaced   = Notification.Name("OpenMaestri.portalWebViewReplaced")
    /// FileTree 根目录变更通知：userInfo 含 nodeId/newPath
    static let fileTreeRootChanged     = Notification.Name("OpenMaestri.fileTreeRootChanged")
    /// 终端从 active→idle（任务完成）：userInfo 含 "terminalId" UUID, "workspaceId" UUID?
    static let terminalBecameIdle      = Notification.Name("OpenMaestri.terminalBecameIdle")
    /// 新工作区创建完成：userInfo 含 "workspaceId" UUID
    static let workspaceCreated        = Notification.Name("OpenMaestri.workspaceCreated")
    /// 画布节点激活（焦点传递给终端）：userInfo 含 "nodeId" UUID
    static let canvasNodeActivated     = Notification.Name("OpenMaestri.canvasNodeActivated")
    /// 画布选中节点变化：userInfo 含 "selectedIds" Set<UUID>
    static let canvasSelectionChanged  = Notification.Name("OpenMaestri.canvasSelectionChanged")
    /// ⌘ 按住跳转数字分配：userInfo 含 "mapping" [UUID: Int]（空 mapping = 清除）
    static let canvasJumpNumbersAssigned = Notification.Name("OpenMaestri.canvasJumpNumbersAssigned")
    /// 文件拖放目标节点变化：userInfo 含可选 "dropTargetNodeId" UUID（nil = 清除高亮）
    static let canvasDropTargetChanged   = Notification.Name("OpenMaestri.canvasDropTargetChanged")
    /// 终端注意力状态变化：userInfo 含 "terminalId" UUID, "needsAttention" Bool
    static let terminalAttentionChanged  = Notification.Name("OpenMaestri.terminalAttentionChanged")
    /// 终端主题/字体变更（立即应用到所有已打开终端）
    static let terminalAppearanceChanged = Notification.Name("OpenMaestri.terminalAppearanceChanged")
    /// 终端当前工作目录变化：userInfo 含 "terminalId" UUID, "directory" String
    static let terminalDirectoryChanged  = Notification.Name("OpenMaestri.terminalDirectoryChanged")
    /// 节点 isLocked 状态变更：userInfo 含 "nodeId" UUID, "isLocked" Bool
    static let canvasNodeLockChanged     = Notification.Name("OpenMaestri.canvasNodeLockChanged")
    /// 节点 content 变更：userInfo 含 "nodeId" UUID, "content" NodeContent
    static let canvasNodeContentChanged  = Notification.Name("OpenMaestri.canvasNodeContentChanged")
}
