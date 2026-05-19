import SwiftUI

struct TerminalNodeSwiftUIView: View {
    let nodeId: UUID
    let content: TerminalContent
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
            title: content.name,
            isSelected: isSelected,
            isLocked: isLocked,
            zoom: zoom,
            headerIcon: content.icon,
            headerColor: Color(hex: content.color),
            onClose: { onClose?(nodeId) },
            onRename: { onRename?(nodeId, $0) },
            onDuplicate: { onDuplicate?(nodeId) },
            onLockToggle: { onLockToggle?(nodeId, $0) }
        ) {
            TerminalEmbeddedView(
                terminalId: content.id,
                command: content.command,
                workingDirectory: content.workingDirectory,
                serverPort: InterAgentServer.shared.port,
                workspaceId: workspace?.id
            )
        }
    }
}
