import Foundation
import OSLog

/// 定时 Routine 配置
struct Routine: Codable, Identifiable {
    var id: UUID
    var name: String
    var prompts: [String]           // 用 && 分隔的多条提示
    var intervalSeconds: TimeInterval
    var targetTerminalId: UUID
    var isActive: Bool
    var createdAt: Date

    init(id: UUID = UUID(), name: String, prompt: String, intervalSeconds: TimeInterval, targetTerminalId: UUID) {
        self.id = id
        self.name = name
        // 解析 && 分隔符
        self.prompts = prompt.components(separatedBy: "&&").map { $0.trimmingCharacters(in: .whitespaces) }
        self.intervalSeconds = intervalSeconds
        self.targetTerminalId = targetTerminalId
        self.isActive = true
        self.createdAt = Date()
    }
}

struct RoutinesContainer: Codable {
    var routines: [Routine]
    init() { self.routines = [] }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 兼容两种字段名：新格式用 routines，旧格式（Maestri原生）用 payload
        if let r = try? container.decode([Routine].self, forKey: .routines) {
            self.routines = r
        } else if let p = try? container.decode([Routine].self, forKey: .payload) {
            self.routines = p
        } else {
            self.routines = []
        }
    }
    private enum CodingKeys: String, CodingKey { case routines, payload }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(routines, forKey: .payload)  // 写入时用 payload 与 Maestri 格式一致
    }
}

/// Routine 定时调度器（FR56-58）
/// - 支持链式提示（&& 分隔，前一条完成后发下一条）
/// - 活跃 Routine 显示绿色脉冲指示器
@MainActor
final class RoutineScheduler {
    static let shared = RoutineScheduler()
    private let logger = Logger.make(category: "RoutineScheduler")
    private var timers: [UUID: Timer] = [:]
    private(set) var routines: [Routine] = []
    private let pm = PersistenceManager.shared

    private init() {}

    // MARK: - 持久化

    func loadRoutines() throws {
        let container = (try? pm.load(RoutinesContainer.self, from: pm.routinesURL)) ?? RoutinesContainer()
        routines = container.routines
        // 恢复活跃 Routine
        for routine in routines where routine.isActive {
            startTimer(for: routine)
        }
    }

    func saveRoutines() throws {
        var container = RoutinesContainer()
        container.routines = routines
        try pm.saveSync(container, to: pm.routinesURL)
    }

    // MARK: - Routine 管理

    func addRoutine(_ routine: Routine) throws {
        routines.append(routine)
        if routine.isActive { startTimer(for: routine) }
        try saveRoutines()
    }

    func removeRoutine(id: UUID) throws {
        stopTimer(for: id)
        routines.removeAll { $0.id == id }
        try saveRoutines()
    }

    func pause(id: UUID) {
        stopTimer(for: id)
        if let idx = routines.firstIndex(where: { $0.id == id }) {
            routines[idx].isActive = false
        }
    }

    func resume(id: UUID) {
        if let idx = routines.firstIndex(where: { $0.id == id }) {
            routines[idx].isActive = true
            startTimer(for: routines[idx])
        }
    }

    // MARK: - 定时器

    private func startTimer(for routine: Routine) {
        let timer = Timer.scheduledTimer(withTimeInterval: routine.intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.executeRoutine(routine)
            }
        }
        timers[routine.id] = timer
        logger.debug("Routine '\(routine.name)' started, interval: \(routine.intervalSeconds)s")
    }

    private func stopTimer(for id: UUID) {
        timers[id]?.invalidate()
        timers.removeValue(forKey: id)
    }

    /// 停止所有 Routine 定时器（应用退出时调用，避免 Timer 回调阻塞主线程）
    func stopAllTimers() {
        for (_, timer) in timers { timer.invalidate() }
        timers.removeAll()
    }

    // MARK: - 执行（链式：等待 Agent 空闲后发下一条）

    private func executeRoutine(_ routine: Routine) async {
        logger.debug("Executing routine '\(routine.name)' — \(routine.prompts.count) prompt(s)")
        let tm = TerminalManager.shared
        for (i, prompt) in routine.prompts.enumerated() {
            guard let session = tm.terminals[routine.targetTerminalId] else { break }
            tm.writeLine(to: routine.targetTerminalId, text: prompt)
            logger.debug("Routine '\(routine.name)' sent prompt \(i+1)/\(routine.prompts.count)")

            // 等待 Agent 变为空闲（最多 5 分钟）
            if i < routine.prompts.count - 1 {
                await waitForIdle(session: session, timeout: 300)
            }
        }
    }

    /// 等待 TerminalSession 恢复空闲状态
    private func waitForIdle(session: TerminalSession, timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        // 先等 Agent 开始响应（最多 3s）
        try? await Task.sleep(for: .seconds(3))
        // 然后等 Agent 完成（输出静止）
        while Date() < deadline {
            if session.isIdle { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
        logger.warning("Routine: Agent idle timeout after \(timeout)s, proceeding anyway")
    }
}
