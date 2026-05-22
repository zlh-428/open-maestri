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
    @State private var currentDirectory: String = ""
    @State private var isCommunicating: Bool = false

    var body: some View {
        NodeShellView(
            nodeId: nodeId,
            title: content.name,
            isSelected: isSelected,
            isLocked: isLocked,
            isCommunicating: isCommunicating,
            zoom: zoom,
            headerIcon: content.icon,
            headerColor: Color(hex: content.color),
            headerAccessory: { headerAccessoryContent },
            footer: {
                if !currentDirectory.isEmpty {
                    TerminalFooterView(directory: currentDirectory)
                }
            },
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
                workspaceId: workspace?.id,
                nodeThemeId: content.themeId,
                nodeFontFamily: content.fontFamily,
                nodeFontSize: content.fontSize
            )
        }
        .onAppear {
            needsAttention = AttentionNotifier.shared.needsAttention(terminalId: content.id)
            // 初始化当前目录：优先从 session 读取，否则使用配置的 workingDirectory
            if let session = TerminalManager.shared.terminals[content.id],
               let dir = session.currentDirectory {
                currentDirectory = dir
            } else if !content.workingDirectory.isEmpty {
                currentDirectory = content.workingDirectory
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .terminalAttentionChanged)) { notification in
            guard let terminalId = notification.userInfo?["terminalId"] as? UUID,
                  terminalId == content.id,
                  let attention = notification.userInfo?["needsAttention"] as? Bool else { return }
            needsAttention = attention
        }
        .onReceive(NotificationCenter.default.publisher(for: .terminalDirectoryChanged)) { notification in
            guard let terminalId = notification.userInfo?["terminalId"] as? UUID,
                  terminalId == content.id,
                  let directory = notification.userInfo?["directory"] as? String else { return }
            currentDirectory = directory
        }
        .onReceive(NotificationCenter.default.publisher(for: .connectionStatusChanged)) { _ in
            isCommunicating = ConnectionManager.shared.connections.values.contains {
                ($0.nodeIdA == content.id || $0.nodeIdB == content.id) && $0.status == .communicating
            }
        }
        .onChange(of: isSelected) { _, selected in
            if selected {
                // 选中时清除注意力标记
                AttentionNotifier.shared.clearAttention(terminalId: content.id)
            }
        }
    }

    // MARK: - Header Accessory（角色徽章 + 注意力圆点）

    @ViewBuilder
    private var headerAccessoryContent: some View {
        HStack(spacing: 4) {
            // 角色徽章
            if content.assignedRoleId != nil {
                roleBadge
            }
            // Maestro 标记
            if content.isManager {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(.purple)
            }
            // 注意力圆点
            if needsAttention {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var roleBadge: some View {
        if let roleName = resolvedRoleName {
            Text(roleName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color(hex: content.color) ?? .blue)
                )
        }
    }

    /// 解析角色名称（从 AppState 中查找）
    private var resolvedRoleName: String? {
        guard let roleId = content.assignedRoleId else { return nil }
        // 从 TerminalManager session 中获取 roleName
        if let session = TerminalManager.shared.terminals[content.id] {
            return session.roleName
        }
        // 回退：显示简短的 Role ID
        return String(roleId.uuidString.prefix(4))
    }
}
