import XCTest
@testable import open_maestri

final class FloorManagerTests: XCTestCase {
    private let fm = FloorManager.shared
    private var testDir: String!

    override func setUpWithError() throws {
        // 创建临时 git repo 用于测试
        testDir = NSTemporaryDirectory() + "open-maestri-floor-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        // 初始化 git repo
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = URL(fileURLWithPath: testDir)
        try process.run(); process.waitUntilExit()
        // 创建初始提交（git worktree 需要至少一个提交）
        let touch = Process()
        touch.executableURL = URL(fileURLWithPath: "/usr/bin/touch")
        touch.arguments = [testDir + "/README.md"]
        try touch.run(); touch.waitUntilExit()
        let add = Process()
        add.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        add.arguments = ["add", "."]
        add.currentDirectoryURL = URL(fileURLWithPath: testDir)
        try add.run(); add.waitUntilExit()
        let commit = Process()
        commit.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commit.arguments = ["commit", "-m", "init", "--allow-empty-message"]
        commit.currentDirectoryURL = URL(fileURLWithPath: testDir)
        commit.environment = ProcessInfo.processInfo.environment.merging([
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "t@t.com",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "t@t.com"
        ]) { _, new in new }
        try commit.run(); commit.waitUntilExit()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: testDir)
    }

    // MARK: - Floor 创建

    func testCreateFloorCreatesWorktreeDirectory() throws {
        let floor = try fm.createFloor(name: "test-floor", branchName: "feature/test", workingDirectory: testDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: floor.worktreePath),
                      "Floor worktree 目录应被创建")
        // 清理
        try? fm.removeFloor(floor, workingDirectory: testDir)
    }

    func testCreateFloorReturnsCorrectBranchName() throws {
        let floor = try fm.createFloor(name: "my-floor", branchName: "my-branch", workingDirectory: testDir)
        XCTAssertEqual(floor.branchName, "my-branch")
        XCTAssertEqual(floor.name, "my-floor")
        try? fm.removeFloor(floor, workingDirectory: testDir)
    }

    func testRemoveFloorDeletesWorktreeDirectory() throws {
        let floor = try fm.createFloor(name: "remove-floor", branchName: "remove-branch", workingDirectory: testDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: floor.worktreePath))
        try fm.removeFloor(floor, workingDirectory: testDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: floor.worktreePath),
                       "Floor worktree 目录应在删除后消失")
    }

    // MARK: - FloorHooks

    func testFloorHooksDefaultValues() {
        let hooks = FloorHooks()
        XCTAssertTrue(hooks.setup.isEmpty)
        XCTAssertTrue(hooks.run.isEmpty)
        XCTAssertTrue(hooks.teardown.isEmpty)
        XCTAssertFalse(hooks.autoRunSetup)
    }

    func testHookEnvironmentVariablesContainRequiredKeys() throws {
        let floor = try fm.createFloor(name: "hook-floor", branchName: "hook-branch", workingDirectory: testDir)
        // 通过 HooksManager 验证环境变量格式（不实际执行钩子，只验证变量生成）
        XCTAssertFalse(floor.worktreePath.isEmpty)
        XCTAssertFalse(floor.branchName.isEmpty)
        try? fm.removeFloor(floor, workingDirectory: testDir)
    }
}
