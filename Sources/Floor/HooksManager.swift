import Foundation
import OSLog

/// Floor Hooks 执行器（Setup/Run/Teardown 生命周期）
final class HooksManager {
    static let shared = HooksManager()
    private let logger = Logger.make(category: "HooksManager")
    private init() {}

    func runSetupHooks(floor: Floor, workingDirectory: String) async throws {
        guard floor.hooks.autoRunSetup else { return }
        try await FloorManager.shared.runHooks(floor.hooks.setup, floor: floor, workingDirectory: workingDirectory)
        logger.info("Setup hooks completed for floor '\(floor.name)'")
    }

    func runRunHooks(floor: Floor, workingDirectory: String) async throws {
        try await FloorManager.shared.runHooks(floor.hooks.run, floor: floor, workingDirectory: workingDirectory)
        logger.info("Run hooks completed for floor '\(floor.name)'")
    }

    func runTeardownHooks(floor: Floor, workingDirectory: String) async throws {
        try await FloorManager.shared.runHooks(floor.hooks.teardown, floor: floor, workingDirectory: workingDirectory)
        logger.info("Teardown hooks completed for floor '\(floor.name)'")
    }
}
