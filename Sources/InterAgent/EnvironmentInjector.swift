import Foundation
import OSLog

/// 环境变量注入器
/// 职责：仅注入 export 语句（无 Shell 函数），用于终端启动时的轻量注入
/// 连接建立后 SkillInjector 会注入完整的 omaestri() 函数（含 json_array）
/// 注意：SwiftTermProvider 启动时已通过 env 字典注入 OMAESTRI_*，
///       本类仅作为后备（如 SSH 终端、手动创建的终端）
final class EnvironmentInjector {
    static let shared = EnvironmentInjector()
    private let logger = Logger.make(category: "EnvironmentInjector")
    private init() {}

    /// 向终端写入环境变量 export 命令（不含 omaestri 函数定义）
    func inject(to terminalId: UUID, serverPort: UInt16) {
        let host = "\(Constants.interAgentServerHost):\(serverPort)"
        let script = [
            "export OMAESTRI_TERMINAL_ID=\"\(terminalId.uuidString)\"",
            "export OMAESTRI_HOST=\"\(host)\"",
            "export MAESTRI_TERMINAL_ID=\"\(terminalId.uuidString)\"",
            "export MAESTRI_HOST=\"\(host)\"",
        ].joined(separator: "\n")
        let id = terminalId
        Task { @MainActor in
            TerminalManager.shared.writeLine(to: id, text: script)
        }
        logger.debug("Env injected to terminal \(terminalId.uuidString.prefix(8)) — host: \(host)")
    }
}
