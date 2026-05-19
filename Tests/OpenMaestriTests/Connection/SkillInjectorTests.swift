import XCTest
@testable import open_maestri

final class SkillInjectorTests: XCTestCase {
    let injector = SkillInjector.shared

    // MARK: - SkillInjector 简化版（CLI 二进制已通过 PATH 注入，不再生成 shell 函数）

    func testInjectorIsSingleton() {
        XCTAssertTrue(SkillInjector.shared === injector, "Should be a singleton")
    }

    func testInjectorExists() {
        // SkillInjector 现在只输出确认信息，不生成 shell 函数
        // inject(to:host:) 方法签名保持向后兼容
        XCTAssertNotNil(injector)
    }
}
