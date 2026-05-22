import Foundation
import OSLog

/// 终端注意力通知管理器
/// 当未选中的终端有重要输出（Agent 完成任务等）时，标记红色注意力点
/// 与 Maestri 的 AttentionNotifier 对齐
///
/// 触发条件（必须全部满足）：
/// 1. 终端 shell 已就绪（completedProviders 中存在）
/// 2. 终端从「运行中」变为「空闲」（表示一段输出完成）
/// 3. 该终端不是当前画布选中节点
@MainActor
final class AttentionNotifier {
    static let shared = AttentionNotifier()
    private let logger = Logger.make(category: "AttentionNotifier")

    /// 需要注意力的终端集合
    private(set) var attentionTerminals: Set<UUID> = []

    /// 当前画布选中的节点 ID 集合（CanvasNode.id == TerminalContent.id）
    private var selectedNodeIds: Set<UUID> = []

    /// 注意力状态变化回调（terminalId, needsAttention）
    var onAttentionChanged: ((UUID, Bool) -> Void)?

    private init() {
        // 监听终端空闲通知（Agent 输出完成，从运行态变为空闲态）
        NotificationCenter.default.addObserver(
            forName: .terminalBecameIdle,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let terminalId = notification.userInfo?["terminalId"] as? UUID else { return }
            Task { @MainActor in
                self.markNeedsAttention(terminalId: terminalId)
            }
        }

        // 监听画布节点激活通知，追踪当前选中节点
        NotificationCenter.default.addObserver(
            forName: .canvasNodeActivated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let nodeId = notification.userInfo?["nodeId"] as? UUID else { return }
            Task { @MainActor in
                self.selectedNodeIds = [nodeId]
                // 选中时自动清除该节点的红点
                self.clearAttention(terminalId: nodeId)
            }
        }
    }

    // MARK: - 标记需要注意力

    /// 标记终端需要注意力（仅由 IPC 任务完成后的 terminalBecameIdle 通知触发）
    func markNeedsAttention(terminalId: UUID) {
        // 当前选中的终端不标记
        if selectedNodeIds.contains(terminalId) { return }

        guard !attentionTerminals.contains(terminalId) else { return }
        attentionTerminals.insert(terminalId)
        onAttentionChanged?(terminalId, true)
        NotificationCenter.default.post(
            name: .terminalAttentionChanged,
            object: nil,
            userInfo: ["terminalId": terminalId, "needsAttention": true]
        )
        logger.debug("Terminal \(terminalId.uuidString.prefix(8)) needs attention")
    }

    // MARK: - 清除注意力

    /// 清除终端注意力标记（用户选中/聚焦终端时调用）
    func clearAttention(terminalId: UUID) {
        guard attentionTerminals.contains(terminalId) else { return }
        attentionTerminals.remove(terminalId)
        onAttentionChanged?(terminalId, false)
        NotificationCenter.default.post(
            name: .terminalAttentionChanged,
            object: nil,
            userInfo: ["terminalId": terminalId, "needsAttention": false]
        )
        logger.debug("Terminal \(terminalId.uuidString.prefix(8)) attention cleared")
    }

    /// 清除所有注意力标记
    func clearAll() {
        let ids = attentionTerminals
        attentionTerminals.removeAll()
        for id in ids {
            onAttentionChanged?(id, false)
            NotificationCenter.default.post(
                name: .terminalAttentionChanged,
                object: nil,
                userInfo: ["terminalId": id, "needsAttention": false]
            )
        }
    }

    // MARK: - 查询

    func needsAttention(terminalId: UUID) -> Bool {
        attentionTerminals.contains(terminalId)
    }
}
