import Foundation
import OSLog

/// Agent 运行/空闲状态检测器
/// 通过 PTY 输出变化判断状态（不依赖 CPU），符合 FR18/Story 3.3 AC
final class TerminalActivityMonitor {
    private let logger = Logger.make(category: "TerminalActivityMonitor")

    private var lastOutputTime: Date = Date()
    private var isRunning: Bool = false
    private var checkTimer: Timer?

    /// 状态变更回调
    var onStatusChanged: ((Bool) -> Void)?  // true = 运行中，false = 空闲

    // MARK: - 启动监控

    func start() {
        checkTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            self?.checkActivity()
        }
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    // MARK: - 输出接收（从 PTY 输出回调调用）

    func recordOutput() {
        lastOutputTime = Date()
        if !isRunning {
            isRunning = true
            onStatusChanged?(true)
        }
    }

    // MARK: - 空闲检测

    private func checkActivity() {
        let elapsed = Date().timeIntervalSince(lastOutputTime)
        if isRunning && elapsed >= Constants.agentIdleTimeout {
            isRunning = false
            onStatusChanged?(false)
        }
    }

    // MARK: - 等待响应完成（用于 omaestri ask）

    /// 等待目标终端输出完成（提示符恢复）
    /// - Parameters:
    ///   - timeout: 最大等待时间（秒）
    ///   - completion: 输出完成后回调，参数为收集到的输出内容
    func waitForResponse(timeout: TimeInterval = 30) async -> String {
        var collected = ""
        var lastActivity = Date()

        // 收集输出直到空闲超时
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            try? await Task.sleep(for: .milliseconds(200))
            if Date().timeIntervalSince(lastOutputTime) >= Constants.agentIdleTimeout {
                break
            }
        }
        return collected
    }
}
