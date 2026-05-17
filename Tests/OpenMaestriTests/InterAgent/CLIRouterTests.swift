import XCTest
@testable import open_maestri

final class CLIRouterTests: XCTestCase {
    let router = CLIRouter.shared
    let testTerminalId = UUID()

    // MARK: - 路由基础（使用 async 接口，避免 @MainActor 死锁）

    func testUnknownCommandReturnsError() async {
        let result = await router.routeAsync(args: ["foobar"], terminalId: testTerminalId)
        XCTAssertTrue(result.hasPrefix("error:"), "Unknown command should return error: \(result)")
    }

    func testEmptyArgsReturnsError() async {
        let result = await router.routeAsync(args: [], terminalId: testTerminalId)
        XCTAssertTrue(result.hasPrefix("error:"))
    }

    func testAskCommandRequiresArgs() async {
        let result = await router.routeAsync(args: ["ask"], terminalId: testTerminalId)
        XCTAssertTrue(result.hasPrefix("error:"))
    }

    func testCheckCommandRequiresArgs() async {
        let result = await router.routeAsync(args: ["check"], terminalId: testTerminalId)
        XCTAssertTrue(result.hasPrefix("error:"))
    }

    func testRecruitRequiresName() async {
        let result = await router.routeAsync(args: ["recruit"], terminalId: testTerminalId)
        XCTAssertTrue(result.hasPrefix("error:"))
    }

    func testDismissRequiresName() async {
        let result = await router.routeAsync(args: ["dismiss"], terminalId: testTerminalId)
        XCTAssertTrue(result.hasPrefix("error:"))
    }

    func testConnectRequiresTwoArgs() async {
        let result = await router.routeAsync(args: ["connect", "A"], terminalId: testTerminalId)
        XCTAssertTrue(result.hasPrefix("error:"))
    }

    func testPortalRequiresSubcommand() async {
        let result = await router.routeAsync(args: ["portal"], terminalId: testTerminalId)
        XCTAssertTrue(result.hasPrefix("error:"))
    }

    func testPortalNavigateRequiresArgs() async {
        let result = await router.routeAsync(args: ["portal", "navigate", "MyPortal"], terminalId: testTerminalId)
        XCTAssertTrue(result.hasPrefix("error:"))
    }

    // MARK: - Note（同步路由，无 @MainActor 依赖）

    func testNoteCommandRequiresSubcommand() {
        let result = router.route(args: ["note"], terminalId: testTerminalId)
        XCTAssertTrue(result.hasPrefix("error:"))
    }

    func testNoteReadRequiresName() {
        let result = router.route(args: ["note", "read"], terminalId: testTerminalId)
        XCTAssertTrue(result.hasPrefix("error:"))
    }

    func testNoteWriteReturnsError_NoteNotFound() {
        // 不存在的 Note 应返回 error（路径不存在）
        let result = router.route(args: ["note", "write", "NonExistentNote", "content"], terminalId: testTerminalId)
        XCTAssertTrue(result.hasPrefix("error:"), "Write to non-existent note should error: \(result)")
    }

    func testNoteEditReturnsError_NoteNotFound() {
        let result = router.route(args: ["note", "edit", "NonExistentNote", "old", "new"], terminalId: testTerminalId)
        XCTAssertTrue(result.hasPrefix("error:"), "Edit on non-existent note should error: \(result)")
    }

    func testNoteUnknownSubcommand() {
        let result = router.route(args: ["note", "foobar"], terminalId: testTerminalId)
        XCTAssertTrue(result.hasPrefix("error:"))
    }

    // MARK: - List / Check（async，需要 @MainActor 但无 terminal 连接）

    func testListWithMissingTerminalIdReturnsError() async {
        let result = await router.routeAsync(args: ["list"], terminalId: nil)
        XCTAssertTrue(result.hasPrefix("error:"))
    }

    func testCheckWithMissingTerminalIdReturnsError() async {
        let result = await router.routeAsync(args: ["check", "Agent"], terminalId: nil)
        XCTAssertTrue(result.hasPrefix("error:"))
    }

    func testListWithUnconnectedTerminalReturnsEmpty() async {
        let unconnectedId = UUID()
        let result = await router.routeAsync(args: ["list"], terminalId: unconnectedId)
        // 有 terminal ID 但无连接，应返回 "No connections"
        XCTAssertFalse(result.hasPrefix("error: missing terminal ID"))
    }
}
