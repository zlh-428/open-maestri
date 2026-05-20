import Foundation
import OSLog

/// Agent 运行/空闲状态检测器
/// 通过 PTY 输出变化判断状态（不依赖 CPU），符合 FR18/Story 3.3 AC
///
/// 性能优化：使用全局共享后台定时器（1s 间隔）替代每个实例独立的 0.5s 主线程 Timer，
/// 避免大量终端时的主线程轮询竞争。
final class TerminalActivityMonitor {
    private let logger = Logger.make(category: "TerminalActivityMonitor")

    private var lastOutputTime: Date = Date()
    private var isRunning: Bool = false
    private var observerToken: NSObjectProtocol?

    /// 状态变更回调（在主线程调用）
    var onStatusChanged: ((Bool) -> Void)?  // true = 运行中，false = 空闲

    // MARK: - 启动监控

    func start() {
        observerToken = GlobalActivityClock.shared.subscribe { [weak self] in
            self?.checkActivity()
        }
    }

    func stop() {
        if let token = observerToken {
            GlobalActivityClock.shared.unsubscribe(token)
            observerToken = nil
        }
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
        // 收集输出直到空闲超时
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            try? await Task.sleep(for: .milliseconds(200))
            if Date().timeIntervalSince(lastOutputTime) >= Constants.agentIdleTimeout {
                break
            }
        }
        return ""
    }
}

// MARK: - 全局共享活动时钟

/// 单一后台定时器，所有 TerminalActivityMonitor 实例共享
/// 替代每个实例创建独立 Timer 的模式，避免 N 个终端产生 N 个主线程 Timer
final class GlobalActivityClock {
    static let shared = GlobalActivityClock()

    private let lock = NSLock()
    private var subscribers: [UUID: () -> Void] = [:]
    private var timer: DispatchSourceTimer?

    private init() {
        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(deadline: .now(), repeating: 1.0, leeway: .milliseconds(200))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let callbacks = Array(self.subscribers.values)
            self.lock.unlock()
            // 在主线程依次调用各 monitor 的检查函数（保证 @MainActor 安全）
            DispatchQueue.main.async {
                callbacks.forEach { $0() }
            }
        }
        source.resume()
        timer = source
    }

    func subscribe(_ callback: @escaping () -> Void) -> NSObjectProtocol {
        let token = UUID()
        lock.lock()
        subscribers[token] = callback
        lock.unlock()
        // 用 NSObject 包装 UUID 作为 token（沿用 NSObjectProtocol 接口）
        return TokenObject(id: token, clock: self)
    }

    func unsubscribe(_ token: NSObjectProtocol) {
        guard let t = token as? TokenObject else { return }
        lock.lock()
        subscribers.removeValue(forKey: t.id)
        lock.unlock()
    }

    private final class TokenObject: NSObject {
        let id: UUID
        weak var clock: GlobalActivityClock?
        init(id: UUID, clock: GlobalActivityClock) {
            self.id = id
            self.clock = clock
        }
    }
}
