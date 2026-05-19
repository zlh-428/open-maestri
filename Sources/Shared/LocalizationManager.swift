import Foundation
import SwiftUI

/// 应用级本地化管理器：支持运行时切换语言（不依赖系统偏好设置）
///
/// 工作原理：
/// 1. 维护当前语言标识（`currentLanguage`），持久化存储在 `Preferences.language`
/// 2. 根据当前语言加载对应 `.lproj` Bundle，用于 `String(localized:bundle:)` 查找
/// 3. 通过 SwiftUI `.environment(\.locale, ...)` 使 `Text` 的 String Catalog 自动匹配
@Observable
@MainActor
final class LocalizationManager {
    static let shared = LocalizationManager()

    /// 当前语言标识，与 Preferences.language 同步
    var currentLanguage: String = "en" {
        didSet {
            if oldValue != currentLanguage {
                updateBundle()
            }
        }
    }

    /// 当前语言对应的 Locale，注入 SwiftUI 环境
    var locale: Locale {
        Locale(identifier: currentLanguage)
    }

    /// 当前语言对应的本地化 Bundle
    private(set) var bundle: Bundle = .main

    /// 支持的语言列表
    static let supportedLanguages: [(id: String, name: String, localName: String)] = [
        ("en", "English", "English"),
        ("zh-Hans", "Chinese (Simplified)", "简体中文"),
    ]

    private init() {
        updateBundle()
    }

    /// 从 Preferences 同步语言设置
    func sync(from language: String) {
        if currentLanguage != language {
            currentLanguage = language
        }
    }

    private func updateBundle() {
        if let path = Bundle.main.path(forResource: currentLanguage, ofType: "lproj"),
           let locBundle = Bundle(path: path) {
            bundle = locBundle
        } else {
            // fallback: 尝试 base
            bundle = .main
        }
    }
}

// MARK: - String 便捷本地化扩展

extension String {
    /// 使用 LocalizationManager 的 bundle 进行本地化
    /// 用法：`"button.cancel".localized`
    @MainActor
    var localized: String {
        String(localized: String.LocalizationValue(self), bundle: LocalizationManager.shared.bundle)
    }
}
