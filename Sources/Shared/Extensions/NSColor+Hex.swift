import AppKit

extension NSColor {
    /// 从 hex 字符串创建 NSColor（支持 "#RRGGBB" 和 "#RRGGBBAA" 格式）
    convenience init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var val: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&val) else { return nil }

        switch h.count {
        case 6:
            self.init(
                red: CGFloat((val >> 16) & 0xFF) / 255,
                green: CGFloat((val >> 8) & 0xFF) / 255,
                blue: CGFloat(val & 0xFF) / 255,
                alpha: 1
            )
        case 8:
            self.init(
                red: CGFloat((val >> 24) & 0xFF) / 255,
                green: CGFloat((val >> 16) & 0xFF) / 255,
                blue: CGFloat((val >> 8) & 0xFF) / 255,
                alpha: CGFloat(val & 0xFF) / 255
            )
        default:
            return nil
        }
    }
}
