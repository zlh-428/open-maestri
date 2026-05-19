import SwiftUI

struct FileTreeNodeSwiftUIView: View {
    let nodeId: UUID
    let content: FileTreeContent
    let isSelected: Bool
    let isLocked: Bool
    let zoom: CGFloat
    let workspace: WorkspaceManager?
    var onActivated: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onDuplicate: ((UUID) -> Void)?
    var onLockToggle: ((UUID, Bool) -> Void)?

    var body: some View {
        NodeShellView(
            nodeId: nodeId,
            title: URL(fileURLWithPath: content.rootPath).lastPathComponent,
            isSelected: isSelected,
            isLocked: isLocked,
            zoom: zoom,
            headerIcon: "folder",
            headerColor: .orange,
            onClose: { onClose?(nodeId) },
            onRename: { onRename?(nodeId, $0) },
            onDuplicate: { onDuplicate?(nodeId) },
            onLockToggle: { onLockToggle?(nodeId, $0) }
        ) {
            FileTreeRepresentable(nodeId: nodeId, content: content, workspace: workspace)
        }
    }
}

struct FileTreeRepresentable: NSViewRepresentable {
    let nodeId: UUID
    let content: FileTreeContent
    let workspace: WorkspaceManager?

    func makeNSView(context: Context) -> NSView {
        let fileTreeView = FileTreeOutlineView(rootPath: content.rootPath)
        return fileTreeView
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
