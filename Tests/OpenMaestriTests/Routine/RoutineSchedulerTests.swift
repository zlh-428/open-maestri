import XCTest
@testable import open_maestri

@MainActor
final class RoutineSchedulerTests: XCTestCase {
    var scheduler: RoutineScheduler!

    override func setUp() async throws {
        scheduler = RoutineScheduler.shared
        // 清理之前的测试数据
        for r in scheduler.routines { scheduler.pause(id: r.id) }
    }

    // MARK: - 基础操作

    func testAddRoutineAppearsInList() throws {
        let routine = makeRoutine(name: "TestRoutine")
        try scheduler.addRoutine(routine)
        XCTAssertTrue(scheduler.routines.contains { $0.id == routine.id })
    }

    func testRemoveRoutineDisappearsFromList() throws {
        let routine = makeRoutine(name: "RemoveMe")
        try scheduler.addRoutine(routine)
        try scheduler.removeRoutine(id: routine.id)
        XCTAssertFalse(scheduler.routines.contains { $0.id == routine.id })
    }

    func testPauseDeactivatesRoutine() throws {
        let routine = makeRoutine(name: "PauseMe")
        try scheduler.addRoutine(routine)
        scheduler.pause(id: routine.id)
        XCTAssertFalse(scheduler.routines.first { $0.id == routine.id }?.isActive ?? true)
    }

    func testResumeActivatesRoutine() throws {
        let routine = makeRoutine(name: "ResumeMe")
        try scheduler.addRoutine(routine)
        scheduler.pause(id: routine.id)
        scheduler.resume(id: routine.id)
        XCTAssertTrue(scheduler.routines.first { $0.id == routine.id }?.isActive ?? false)
    }

    // MARK: - && 分隔符解析

    func testPromptParsingWithSeparator() {
        // Routine 的 && 分隔：用 "&&" 分隔（不含换行）
        let routine = Routine(
            name: "Chain",
            prompt: "run tests&&check results&&summarize",
            intervalSeconds: 60,
            targetTerminalId: UUID()
        )
        XCTAssertEqual(routine.prompts.count, 3,
                       "&&分隔应产生 3 条提示，实际：\(routine.prompts)")
        XCTAssertEqual(routine.prompts[0].trimmingCharacters(in: .whitespaces), "run tests")
        XCTAssertEqual(routine.prompts[1].trimmingCharacters(in: .whitespaces), "check results")
        XCTAssertEqual(routine.prompts[2].trimmingCharacters(in: .whitespaces), "summarize")
    }

    func testSinglePromptNoSeparator() {
        let routine = Routine(
            name: "Single",
            prompt: "run tests",
            intervalSeconds: 60,
            targetTerminalId: UUID()
        )
        XCTAssertEqual(routine.prompts.count, 1)
    }

    // MARK: - 持久化

    func testSaveAndLoadRoutines() throws {
        let routine = makeRoutine(name: "Persist")
        try scheduler.addRoutine(routine)
        try scheduler.saveRoutines()

        // 重新加载
        try scheduler.loadRoutines()
        XCTAssertTrue(scheduler.routines.contains { $0.name == "Persist" })

        // 清理
        try? scheduler.removeRoutine(id: routine.id)
    }

    // MARK: - 辅助

    private func makeRoutine(name: String) -> Routine {
        Routine(name: name, prompt: "test", intervalSeconds: 3600, targetTerminalId: UUID())
    }
}
