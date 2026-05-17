import Foundation

extension Date {
    /// ISO 8601 UTC 字符串（与 Maestri 数据格式一致）
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }

    /// 从 ISO 8601 字符串解析
    static func from(iso8601 string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}
