import AppKit
import SwiftTerm

/// 终端主题定义
struct TerminalTheme: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let foreground: String       // hex
    let background: String       // hex
    let cursor: String           // hex
    let selection: String        // hex
    let ansiBlack: String
    let ansiRed: String
    let ansiGreen: String
    let ansiYellow: String
    let ansiBlue: String
    let ansiMagenta: String
    let ansiCyan: String
    let ansiWhite: String
    let ansiBrightBlack: String
    let ansiBrightRed: String
    let ansiBrightGreen: String
    let ansiBrightYellow: String
    let ansiBrightBlue: String
    let ansiBrightMagenta: String
    let ansiBrightCyan: String
    let ansiBrightWhite: String
}

/// 终端主题注册表
/// 管理所有内置主题，提供应用主题到 TerminalView 的能力
@MainActor
final class TerminalThemeRegistry {
    static let shared = TerminalThemeRegistry()

    private(set) var themes: [TerminalTheme] = []

    private init() {
        themes = Self.builtInThemes
    }

    /// 根据 ID 获取主题
    func theme(for id: String) -> TerminalTheme? {
        themes.first { $0.id == id }
    }

    /// 将主题应用到终端视图（即时生效）
    func apply(themeId: String, to terminalView: LocalProcessTerminalView) {
        guard let theme = theme(for: themeId) else {
            // 回退到系统默认
            terminalView.configureNativeColors()
            return
        }
        apply(theme: theme, to: terminalView)
    }

    /// 将主题应用到终端视图
    func apply(theme: TerminalTheme, to terminalView: LocalProcessTerminalView) {
        terminalView.nativeForegroundColor = NSColor(hex: theme.foreground) ?? .textColor
        terminalView.nativeBackgroundColor = NSColor(hex: theme.background) ?? .textBackgroundColor
        terminalView.caretColor = NSColor(hex: theme.cursor) ?? .textColor
        terminalView.selectedTextBackgroundColor = NSColor(hex: theme.selection) ?? .selectedTextBackgroundColor

        // 设置 ANSI 16 色（使用 SwiftTerm.Color，范围 0-65535）
        let paletteColors: [SwiftTerm.Color] = [
            Self.swiftTermColor(hex: theme.ansiBlack),
            Self.swiftTermColor(hex: theme.ansiRed),
            Self.swiftTermColor(hex: theme.ansiGreen),
            Self.swiftTermColor(hex: theme.ansiYellow),
            Self.swiftTermColor(hex: theme.ansiBlue),
            Self.swiftTermColor(hex: theme.ansiMagenta),
            Self.swiftTermColor(hex: theme.ansiCyan),
            Self.swiftTermColor(hex: theme.ansiWhite),
            Self.swiftTermColor(hex: theme.ansiBrightBlack),
            Self.swiftTermColor(hex: theme.ansiBrightRed),
            Self.swiftTermColor(hex: theme.ansiBrightGreen),
            Self.swiftTermColor(hex: theme.ansiBrightYellow),
            Self.swiftTermColor(hex: theme.ansiBrightBlue),
            Self.swiftTermColor(hex: theme.ansiBrightMagenta),
            Self.swiftTermColor(hex: theme.ansiBrightCyan),
            Self.swiftTermColor(hex: theme.ansiBrightWhite),
        ]
        terminalView.installColors(paletteColors)
        terminalView.getTerminal().updateFullScreen()
    }

    /// 将 hex 字符串转为 SwiftTerm.Color（16-bit RGB）
    private static func swiftTermColor(hex: String) -> SwiftTerm.Color {
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexStr.hasPrefix("#") { hexStr.removeFirst() }
        guard hexStr.count == 6, let value = UInt32(hexStr, radix: 16) else {
            return SwiftTerm.Color(red: 0, green: 0, blue: 0)
        }
        let r = UInt16((value >> 16) & 0xFF) * 257
        let g = UInt16((value >> 8) & 0xFF) * 257
        let b = UInt16(value & 0xFF) * 257
        return SwiftTerm.Color(red: r, green: g, blue: b)
    }

    /// 根据偏好推断要使用的主题 ID
    /// "system" 模式会根据系统外观自动选择 dark/light
    static func resolveThemeId(from preference: String) -> String {
        switch preference {
        case "dark":
            return "maestri-dark"
        case "light":
            return "maestri-light"
        case "dracula":
            return "dracula"
        case "solarized-dark":
            return "solarized-dark"
        case "solarized-light":
            return "solarized-light"
        case "nord":
            return "nord"
        case "one-dark":
            return "one-dark"
        case "tokyo-night":
            return "tokyo-night"
        default:
            // "system"：根据系统外观决定
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? "maestri-dark" : "maestri-light"
        }
    }

    // MARK: - 内置主题

    static let builtInThemes: [TerminalTheme] = [
        // Maestri 默认深色
        TerminalTheme(
            id: "maestri-dark",
            name: "Maestri Dark",
            foreground: "#D4D4D4",
            background: "#1E1E1E",
            cursor: "#AEAFAD",
            selection: "#264F78",
            ansiBlack: "#000000",
            ansiRed: "#CD3131",
            ansiGreen: "#0DBC79",
            ansiYellow: "#E5E510",
            ansiBlue: "#2472C8",
            ansiMagenta: "#BC3FBC",
            ansiCyan: "#11A8CD",
            ansiWhite: "#E5E5E5",
            ansiBrightBlack: "#666666",
            ansiBrightRed: "#F14C4C",
            ansiBrightGreen: "#23D18B",
            ansiBrightYellow: "#F5F543",
            ansiBrightBlue: "#3B8EEA",
            ansiBrightMagenta: "#D670D6",
            ansiBrightCyan: "#29B8DB",
            ansiBrightWhite: "#FFFFFF"
        ),
        // Maestri 默认浅色
        TerminalTheme(
            id: "maestri-light",
            name: "Maestri Light",
            foreground: "#383A42",
            background: "#FFFFFF",
            cursor: "#526FFF",
            selection: "#ADD6FF",
            ansiBlack: "#000000",
            ansiRed: "#CD3131",
            ansiGreen: "#008000",
            ansiYellow: "#949800",
            ansiBlue: "#0451A5",
            ansiMagenta: "#BC05BC",
            ansiCyan: "#0598BC",
            ansiWhite: "#E5E5E5",
            ansiBrightBlack: "#666666",
            ansiBrightRed: "#CD3131",
            ansiBrightGreen: "#14CE14",
            ansiBrightYellow: "#B5BA00",
            ansiBrightBlue: "#0451A5",
            ansiBrightMagenta: "#BC05BC",
            ansiBrightCyan: "#0598BC",
            ansiBrightWhite: "#A5A5A5"
        ),
        // Dracula
        TerminalTheme(
            id: "dracula",
            name: "Dracula",
            foreground: "#F8F8F2",
            background: "#282A36",
            cursor: "#F8F8F2",
            selection: "#44475A",
            ansiBlack: "#21222C",
            ansiRed: "#FF5555",
            ansiGreen: "#50FA7B",
            ansiYellow: "#F1FA8C",
            ansiBlue: "#BD93F9",
            ansiMagenta: "#FF79C6",
            ansiCyan: "#8BE9FD",
            ansiWhite: "#F8F8F2",
            ansiBrightBlack: "#6272A4",
            ansiBrightRed: "#FF6E6E",
            ansiBrightGreen: "#69FF94",
            ansiBrightYellow: "#FFFFA5",
            ansiBrightBlue: "#D6ACFF",
            ansiBrightMagenta: "#FF92DF",
            ansiBrightCyan: "#A4FFFF",
            ansiBrightWhite: "#FFFFFF"
        ),
        // Solarized Dark
        TerminalTheme(
            id: "solarized-dark",
            name: "Solarized Dark",
            foreground: "#839496",
            background: "#002B36",
            cursor: "#839496",
            selection: "#073642",
            ansiBlack: "#073642",
            ansiRed: "#DC322F",
            ansiGreen: "#859900",
            ansiYellow: "#B58900",
            ansiBlue: "#268BD2",
            ansiMagenta: "#D33682",
            ansiCyan: "#2AA198",
            ansiWhite: "#EEE8D5",
            ansiBrightBlack: "#002B36",
            ansiBrightRed: "#CB4B16",
            ansiBrightGreen: "#586E75",
            ansiBrightYellow: "#657B83",
            ansiBrightBlue: "#839496",
            ansiBrightMagenta: "#6C71C4",
            ansiBrightCyan: "#93A1A1",
            ansiBrightWhite: "#FDF6E3"
        ),
        // Solarized Light
        TerminalTheme(
            id: "solarized-light",
            name: "Solarized Light",
            foreground: "#657B83",
            background: "#FDF6E3",
            cursor: "#657B83",
            selection: "#EEE8D5",
            ansiBlack: "#073642",
            ansiRed: "#DC322F",
            ansiGreen: "#859900",
            ansiYellow: "#B58900",
            ansiBlue: "#268BD2",
            ansiMagenta: "#D33682",
            ansiCyan: "#2AA198",
            ansiWhite: "#EEE8D5",
            ansiBrightBlack: "#002B36",
            ansiBrightRed: "#CB4B16",
            ansiBrightGreen: "#586E75",
            ansiBrightYellow: "#657B83",
            ansiBrightBlue: "#839496",
            ansiBrightMagenta: "#6C71C4",
            ansiBrightCyan: "#93A1A1",
            ansiBrightWhite: "#FDF6E3"
        ),
        // Nord
        TerminalTheme(
            id: "nord",
            name: "Nord",
            foreground: "#D8DEE9",
            background: "#2E3440",
            cursor: "#D8DEE9",
            selection: "#434C5E",
            ansiBlack: "#3B4252",
            ansiRed: "#BF616A",
            ansiGreen: "#A3BE8C",
            ansiYellow: "#EBCB8B",
            ansiBlue: "#81A1C1",
            ansiMagenta: "#B48EAD",
            ansiCyan: "#88C0D0",
            ansiWhite: "#E5E9F0",
            ansiBrightBlack: "#4C566A",
            ansiBrightRed: "#BF616A",
            ansiBrightGreen: "#A3BE8C",
            ansiBrightYellow: "#EBCB8B",
            ansiBrightBlue: "#81A1C1",
            ansiBrightMagenta: "#B48EAD",
            ansiBrightCyan: "#8FBCBB",
            ansiBrightWhite: "#ECEFF4"
        ),
        // One Dark
        TerminalTheme(
            id: "one-dark",
            name: "One Dark",
            foreground: "#ABB2BF",
            background: "#282C34",
            cursor: "#528BFF",
            selection: "#3E4451",
            ansiBlack: "#282C34",
            ansiRed: "#E06C75",
            ansiGreen: "#98C379",
            ansiYellow: "#E5C07B",
            ansiBlue: "#61AFEF",
            ansiMagenta: "#C678DD",
            ansiCyan: "#56B6C2",
            ansiWhite: "#ABB2BF",
            ansiBrightBlack: "#5C6370",
            ansiBrightRed: "#E06C75",
            ansiBrightGreen: "#98C379",
            ansiBrightYellow: "#E5C07B",
            ansiBrightBlue: "#61AFEF",
            ansiBrightMagenta: "#C678DD",
            ansiBrightCyan: "#56B6C2",
            ansiBrightWhite: "#FFFFFF"
        ),
        // Tokyo Night
        TerminalTheme(
            id: "tokyo-night",
            name: "Tokyo Night",
            foreground: "#A9B1D6",
            background: "#1A1B26",
            cursor: "#C0CAF5",
            selection: "#33467C",
            ansiBlack: "#15161E",
            ansiRed: "#F7768E",
            ansiGreen: "#9ECE6A",
            ansiYellow: "#E0AF68",
            ansiBlue: "#7AA2F7",
            ansiMagenta: "#BB9AF7",
            ansiCyan: "#7DCFFF",
            ansiWhite: "#A9B1D6",
            ansiBrightBlack: "#414868",
            ansiBrightRed: "#F7768E",
            ansiBrightGreen: "#9ECE6A",
            ansiBrightYellow: "#E0AF68",
            ansiBrightBlue: "#7AA2F7",
            ansiBrightMagenta: "#BB9AF7",
            ansiBrightCyan: "#7DCFFF",
            ansiBrightWhite: "#C0CAF5"
        ),
    ]
}

