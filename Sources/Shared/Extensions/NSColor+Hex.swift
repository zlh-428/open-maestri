import AppKit

extension NSColor {
    /// 将 NSColor 转为 "#RRGGBB" 格式字符串
    var hexString: String {
        guard let rgb = self.usingColorSpace(.deviceRGB) else { return "#FEFDE8" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

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
