import SwiftUI

/// 终端折叠态预览视图
/// 当终端节点缩小到一定尺寸（或画布缩放到较小比例）时，
/// 自动切换为轻量预览模式，减少 GPU/CPU 开销。
/// 对齐 Maestri 的 TerminalPreviewEmbeddedView 设计。
struct TerminalPreviewEmbeddedView: View {
    let terminalId: UUID
    let content: TerminalContent
    let nodeSize: CGSize

    /// 是否应该显示预览模式（节点太小时切换）
    static func shouldShowPreview(nodeSize: CGSize, zoom: CGFloat) -> Bool {
        let effectiveWidth = nodeSize.width * zoom
        let effectiveHeight = nodeSize.height * zoom
        return effectiveWidth < 180 || effectiveHeight < 100
    }

    var body: some View {
        VStack(spacing: 6) {
            // Agent 图标
            Image(systemName: content.icon)
                .font(.system(size: 24))
                .foregroundStyle(Color(hex: content.color) ?? .blue)

            // Agent 名称
            Text(content.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)

            // 状态指示
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var statusColor: Color {
        if let session = TerminalManager.shared.terminals[terminalId] {
            return session.isIdle ? .green : .orange
        }
        return .gray
    }

    private var statusText: String {
        if let session = TerminalManager.shared.terminals[terminalId] {
            return session.isIdle ? "Idle" : "Running"
        }
        return "Inactive"
    }
}
