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
    /// 自定义主题直接返回其 ID
    static func resolveThemeId(from preference: String) -> String {
        switch preference {
        case "system":
            // 根据系统外观决定
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? "maestri-dark" : "maestri-light"
        case "dark":
            return "maestri-dark"
        case "light":
            return "maestri-light"
        default:
            // 自定义主题：直接使用 ID（如 dracula, nord, catppuccin-mocha 等）
            // 验证主题是否存在，不存在则回退到系统
            if TerminalThemeRegistry.shared.theme(for: preference) != nil {
                return preference
            }
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
        // Tokyo Night Day
        TerminalTheme(
            id: "tokyo-night-day",
            name: "Tokyo Night Day",
            foreground: "#3760BF",
            background: "#E1E2E7",
            cursor: "#3760BF",
            selection: "#B6BFE2",
            ansiBlack: "#E9E9ED",
            ansiRed: "#F52A65",
            ansiGreen: "#587539",
            ansiYellow: "#8C6C3E",
            ansiBlue: "#2E7DE9",
            ansiMagenta: "#9854F1",
            ansiCyan: "#007197",
            ansiWhite: "#6172B0",
            ansiBrightBlack: "#A1A6C5",
            ansiBrightRed: "#F52A65",
            ansiBrightGreen: "#587539",
            ansiBrightYellow: "#8C6C3E",
            ansiBrightBlue: "#2E7DE9",
            ansiBrightMagenta: "#9854F1",
            ansiBrightCyan: "#007197",
            ansiBrightWhite: "#3760BF"
        ),
        // Catppuccin Mocha
        TerminalTheme(
            id: "catppuccin-mocha",
            name: "Catppuccin Mocha",
            foreground: "#CDD6F4",
            background: "#1E1E2E",
            cursor: "#F5E0DC",
            selection: "#45475A",
            ansiBlack: "#45475A",
            ansiRed: "#F38BA8",
            ansiGreen: "#A6E3A1",
            ansiYellow: "#F9E2AF",
            ansiBlue: "#89B4FA",
            ansiMagenta: "#F5C2E7",
            ansiCyan: "#94E2D5",
            ansiWhite: "#BAC2DE",
            ansiBrightBlack: "#585B70",
            ansiBrightRed: "#F38BA8",
            ansiBrightGreen: "#A6E3A1",
            ansiBrightYellow: "#F9E2AF",
            ansiBrightBlue: "#89B4FA",
            ansiBrightMagenta: "#F5C2E7",
            ansiBrightCyan: "#94E2D5",
            ansiBrightWhite: "#A6ADC8"
        ),
        // Catppuccin Macchiato
        TerminalTheme(
            id: "catppuccin-macchiato",
            name: "Catppuccin Macchiato",
            foreground: "#CAD3F5",
            background: "#24273A",
            cursor: "#F4DBD6",
            selection: "#494D64",
            ansiBlack: "#494D64",
            ansiRed: "#ED8796",
            ansiGreen: "#A6DA95",
            ansiYellow: "#EED49F",
            ansiBlue: "#8AADF4",
            ansiMagenta: "#F5BDE6",
            ansiCyan: "#8BD5CA",
            ansiWhite: "#B8C0E0",
            ansiBrightBlack: "#5B6078",
            ansiBrightRed: "#ED8796",
            ansiBrightGreen: "#A6DA95",
            ansiBrightYellow: "#EED49F",
            ansiBrightBlue: "#8AADF4",
            ansiBrightMagenta: "#F5BDE6",
            ansiBrightCyan: "#8BD5CA",
            ansiBrightWhite: "#A5ADCB"
        ),
        // Catppuccin Latte
        TerminalTheme(
            id: "catppuccin-latte",
            name: "Catppuccin Latte",
            foreground: "#4C4F69",
            background: "#EFF1F5",
            cursor: "#DC8A78",
            selection: "#ACB0BE",
            ansiBlack: "#5C5F77",
            ansiRed: "#D20F39",
            ansiGreen: "#40A02B",
            ansiYellow: "#DF8E1D",
            ansiBlue: "#1E66F5",
            ansiMagenta: "#EA76CB",
            ansiCyan: "#179299",
            ansiWhite: "#ACB0BE",
            ansiBrightBlack: "#6C6F85",
            ansiBrightRed: "#D20F39",
            ansiBrightGreen: "#40A02B",
            ansiBrightYellow: "#DF8E1D",
            ansiBrightBlue: "#1E66F5",
            ansiBrightMagenta: "#EA76CB",
            ansiBrightCyan: "#179299",
            ansiBrightWhite: "#BCC0CC"
        ),
        // Gruvbox Dark
        TerminalTheme(
            id: "gruvbox-dark",
            name: "Gruvbox Dark",
            foreground: "#EBDBB2",
            background: "#282828",
            cursor: "#EBDBB2",
            selection: "#504945",
            ansiBlack: "#282828",
            ansiRed: "#CC241D",
            ansiGreen: "#98971A",
            ansiYellow: "#D79921",
            ansiBlue: "#458588",
            ansiMagenta: "#B16286",
            ansiCyan: "#689D6A",
            ansiWhite: "#A89984",
            ansiBrightBlack: "#928374",
            ansiBrightRed: "#FB4934",
            ansiBrightGreen: "#B8BB26",
            ansiBrightYellow: "#FABD2F",
            ansiBrightBlue: "#83A598",
            ansiBrightMagenta: "#D3869B",
            ansiBrightCyan: "#8EC07C",
            ansiBrightWhite: "#EBDBB2"
        ),
        // Gruvbox Light
        TerminalTheme(
            id: "gruvbox-light",
            name: "Gruvbox Light",
            foreground: "#3C3836",
            background: "#FBF1C7",
            cursor: "#3C3836",
            selection: "#D5C4A1",
            ansiBlack: "#FBF1C7",
            ansiRed: "#CC241D",
            ansiGreen: "#98971A",
            ansiYellow: "#D79921",
            ansiBlue: "#458588",
            ansiMagenta: "#B16286",
            ansiCyan: "#689D6A",
            ansiWhite: "#7C6F64",
            ansiBrightBlack: "#928374",
            ansiBrightRed: "#9D0006",
            ansiBrightGreen: "#79740E",
            ansiBrightYellow: "#B57614",
            ansiBrightBlue: "#076678",
            ansiBrightMagenta: "#8F3F71",
            ansiBrightCyan: "#427B58",
            ansiBrightWhite: "#3C3836"
        ),
        // Rosé Pine
        TerminalTheme(
            id: "rose-pine",
            name: "Rosé Pine",
            foreground: "#E0DEF4",
            background: "#191724",
            cursor: "#524F67",
            selection: "#2A283E",
            ansiBlack: "#26233A",
            ansiRed: "#EB6F92",
            ansiGreen: "#31748F",
            ansiYellow: "#F6C177",
            ansiBlue: "#9CCFD8",
            ansiMagenta: "#C4A7E7",
            ansiCyan: "#EBBCBA",
            ansiWhite: "#E0DEF4",
            ansiBrightBlack: "#6E6A86",
            ansiBrightRed: "#EB6F92",
            ansiBrightGreen: "#31748F",
            ansiBrightYellow: "#F6C177",
            ansiBrightBlue: "#9CCFD8",
            ansiBrightMagenta: "#C4A7E7",
            ansiBrightCyan: "#EBBCBA",
            ansiBrightWhite: "#E0DEF4"
        ),
    ]
}

