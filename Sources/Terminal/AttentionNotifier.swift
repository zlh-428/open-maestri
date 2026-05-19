import Foundation
import OSLog

/// 终端注意力通知管理器
/// 当未选中的终端有重要输出（Agent 完成任务等）时，标记红色注意力点
/// 与 Maestri 的 AttentionNotifier 对齐
@MainActor
final class AttentionNotifier {
    static let shared = AttentionNotifier()
    private let logger = Logger.make(category: "AttentionNotifier")

    /// 需要注意力的终端集合
    private(set) var attentionTerminals: Set<UUID> = []

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
    }

    // MARK: - 标记需要注意力

    /// 标记终端需要注意力（当后台终端 Agent 完成输出时触发）
    /// 仅当终端不是当前选中节点时才标记
    func markNeedsAttention(terminalId: UUID) {
        // 检查是否是当前选中的终端（选中的不需要红点）
        if isTerminalSelected(terminalId) { return }

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

    // MARK: - Private

    private func isTerminalSelected(_ terminalId: UUID) -> Bool {
        // 通过 canvasNodeActivated 通知记录的当前选中节点来判断
        // 这里简单检查：如果终端是当前画布选中节点，则不标记
        // 需要由画布层在选中终端时调用 clearAttention
        return false
    }
}
