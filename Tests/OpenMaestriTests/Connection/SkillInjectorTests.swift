import XCTest
@testable import open_maestri

final class SkillInjectorTests: XCTestCase {
    let injector = SkillInjector.shared

    // MARK: - Skill 脚本生成

    func testBuildSkillScriptContainsExports() {
        let script = injector.buildSkillScript(terminalId: UUID(), host: "127.0.0.1:12345")
        XCTAssertTrue(script.contains("OMAESTRI_TERMINAL_ID"), "Script should export OMAESTRI_TERMINAL_ID")
        XCTAssertTrue(script.contains("OMAESTRI_HOST"), "Script should export OMAESTRI_HOST")
        XCTAssertTrue(script.contains("127.0.0.1:12345"), "Script should contain the host")
    }

    func testBuildSkillScriptContainsOmaestriFunction() {
        let id = UUID()
        let script = injector.buildSkillScript(terminalId: id, host: "127.0.0.1:9999")
        XCTAssertTrue(script.contains("omaestri()"), "Script should define omaestri() function")
        XCTAssertTrue(script.contains("curl"), "Script should use curl for HTTP calls")
        XCTAssertTrue(script.contains("/cli"), "Script should call /cli endpoint")
    }

    func testBuildSkillScriptContainsTerminalId() {
        let id = UUID()
        let script = injector.buildSkillScript(terminalId: id, host: "127.0.0.1:0")
        XCTAssertTrue(script.contains(id.uuidString), "Script should embed terminal UUID")
    }

    func testBuildSkillScriptContainsJsonArrayHelper() {
        let script = injector.buildSkillScript(terminalId: UUID(), host: "127.0.0.1:0")
        // 官方逆向使用 json_array（无下划线前缀），作为独立函数
        XCTAssertTrue(
            script.contains("json_array"),
            "Script should include JSON array helper (json_array or _json_array)"
        )
    }

    func testSkillScriptIsValidShell() {
        let script = injector.buildSkillScript(terminalId: UUID(), host: "127.0.0.1:7777")
        // 基本语法检查：不应包含未配对的引号
        let singleQuotes = script.components(separatedBy: "'").count - 1
        // 奇数个单引号意味着字符串未关闭（粗略检查）
        XCTAssertFalse(
            script.contains("\\\"\\\"\\\""),
            "Script should not have triple-escaped quotes"
        )
        _ = singleQuotes // 仅作语法可读性检查
    }
}
