import Foundation

/// AppKit 层（CanvasNodesView）向 SwiftUI 层（FileTreeNodeSwiftUIView）传递菜单操作的中继。
/// 使用 NotificationCenter 广播，SwiftUI 视图通过 .onReceive 监听后修改自身 @State。
enum NavBarMenuAction {
    static let setViewMode  = Notification.Name("NavBarMenu.setViewMode")
    static let toggleHidden = Notification.Name("NavBarMenu.toggleHidden")
    static let collapseAll  = Notification.Name("NavBarMenu.collapseAll")

    static let nodeIdKey   = "nodeId"
    static let viewModeKey = "viewMode"
}

final class NavBarMenuActionRelay {
    static let shared = NavBarMenuActionRelay()
    private init() {}

    func setViewMode(_ mode: FileTreeViewMode, for nodeId: UUID) {
        NotificationCenter.default.post(
            name: NavBarMenuAction.setViewMode,
            object: nil,
            userInfo: [NavBarMenuAction.nodeIdKey: nodeId,
                       NavBarMenuAction.viewModeKey: mode]
        )
    }

    func toggleHidden(for nodeId: UUID) {
        NotificationCenter.default.post(
            name: NavBarMenuAction.toggleHidden,
            object: nil,
            userInfo: [NavBarMenuAction.nodeIdKey: nodeId]
        )
    }

    func collapseAll(for nodeId: UUID) {
        NotificationCenter.default.post(
            name: NavBarMenuAction.collapseAll,
            object: nil,
            userInfo: [NavBarMenuAction.nodeIdKey: nodeId]
        )
    }
}
