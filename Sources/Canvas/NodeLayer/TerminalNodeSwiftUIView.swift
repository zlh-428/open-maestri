import SwiftUI

struct TerminalNodeSwiftUIView: View {
    let nodeId: UUID
    let content: TerminalContent
    let isSelected: Bool
    let isLocked: Bool
    let zoom: CGFloat
    let nodeSize: CGSize
    let workspace: WorkspaceManager?
    var onActivated: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onDuplicate: ((UUID) -> Void)?
    var onLockToggle: ((UUID, Bool) -> Void)?

    @State private var needsAttention: Bool = false

    var body: some View {
        NodeShellView(
            nodeId: nodeId,
            title: content.name,
            isSelected: isSelected,
            isLocked: isLocked,
            zoom: zoom,
            headerIcon: content.icon,
            headerColor: Color(hex: content.color),
            headerAccessory: { attentionDot },
            onClose: { onClose?(nodeId) },
            onRename: { onRename?(nodeId, $0) },
            onDuplicate: { onDuplicate?(nodeId) },
            onLockToggle: { onLockToggle?(nodeId, $0) }
        ) {
            if TerminalPreviewEmbeddedView.shouldShowPreview(nodeSize: nodeSize, zoom: zoom) {
                TerminalPreviewEmbeddedView(
                    terminalId: content.id,
                    content: content,
                    nodeSize: nodeSize
                )
            } else {
                TerminalEmbeddedView(
                    terminalId: content.id,
                    command: content.command,
                    workingDirectory: content.workingDirectory,
                    serverPort: InterAgentServer.shared.port,
                    workspaceId: workspace?.id
                )
            }
        }
        .onAppear {
            needsAttention = AttentionNotifier.shared.needsAttention(terminalId: content.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .terminalAttentionChanged)) { notification in
            guard let terminalId = notification.userInfo?["terminalId"] as? UUID,
                  terminalId == content.id,
                  let attention = notification.userInfo?["needsAttention"] as? Bool else { return }
            needsAttention = attention
        }
        .onChange(of: isSelected) { _, selected in
            if selected {
                // 选中时清除注意力标记
                AttentionNotifier.shared.clearAttention(terminalId: content.id)
            }
        }
    }

    @ViewBuilder
    private var attentionDot: some View {
        if needsAttention {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .transition(.scale.combined(with: .opacity))
        }
    }
}
