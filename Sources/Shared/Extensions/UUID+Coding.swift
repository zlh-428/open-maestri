import Foundation

extension UUID {
    /// 从字符串创建 UUID（方便 Codable 解码）
    init?(uuidString: String?) {
        guard let str = uuidString else { return nil }
        self.init(uuidString: str)
    }
}
