// Sources/Connection/SkillInjector.swift
import Foundation
import OSLog

/// Skill 注入器（简化版）
/// CLI 二进制已通过 SwiftTermProvider 的 PATH 注入，此处只输出确认信息
final class SkillInjector {
    static let shared = SkillInjector()
    private let logger = Logger.make(category: "SkillInjector")
    private init() {}

    func inject(to terminalId: UUID, host: String) {
        let id = terminalId
        Task { @MainActor in
            TerminalManager.shared.write(
                to: id,
                text: "echo \"✅ omaestri ready (terminal: \(terminalId.uuidString))\"\n"
            )
        }
        logger.debug("Skill ready signal sent to terminal \(terminalId.uuidString.prefix(8))")
    }
}
