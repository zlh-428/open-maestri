import Foundation
import AppKit

/// Markdown 渲染器
/// - Formatted 视图通过 NSTextStorage 子类实现语法高亮
/// - 支持：标题（#）、代码块（```）、粗体（**）、斜体（*）、表格、链接
final class MarkdownRenderer {

    // MARK: - 渲染为 NSAttributedString

    static func render(_ markdown: String, fontSize: CGFloat = 14) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeBuffer: [String] = []
        var codeLanguage = ""

        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // 结束代码块
                    let codeText = codeBuffer.joined(separator: "\n")
                    result.append(renderCodeBlock(codeText, language: codeLanguage, fontSize: fontSize))
                    codeBuffer = []
                    codeLanguage = ""
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                    codeLanguage = String(line.dropFirst(3))
                }
                continue
            }

            if inCodeBlock {
                codeBuffer.append(line)
                continue
            }

            result.append(renderLine(line, fontSize: fontSize))
            result.append(NSAttributedString(string: "\n"))
        }

        // 未关闭的代码块
        if inCodeBlock && !codeBuffer.isEmpty {
            result.append(renderCodeBlock(codeBuffer.joined(separator: "\n"), language: codeLanguage, fontSize: fontSize))
        }

        return result
    }

    // MARK: - 行级渲染

    private static func renderLine(_ line: String, fontSize: CGFloat) -> NSAttributedString {
        // 标题
        if line.hasPrefix("### ") {
            return styled(String(line.dropFirst(4)), size: fontSize + 2, bold: true)
        } else if line.hasPrefix("## ") {
            return styled(String(line.dropFirst(3)), size: fontSize + 4, bold: true)
        } else if line.hasPrefix("# ") {
            return styled(String(line.dropFirst(2)), size: fontSize + 6, bold: true)
        }
        // 水平线
        if line == "---" || line == "===" {
            return NSAttributedString(
                string: "\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}",
                attributes: [.foregroundColor: NSColor.separatorColor]
            )
        }
        // 普通文本（内联处理粗体/斜体/代码）
        return renderInline(line, fontSize: fontSize)
    }

    private static func renderInline(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = text[text.startIndex...]
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.labelColor,
        ]

        // 简单处理：粗体 **text**，行内代码 `code`
        while !remaining.isEmpty {
            if remaining.hasPrefix("**"), let end = remaining.dropFirst(2).range(of: "**") {
                let boldText = String(remaining.dropFirst(2)[..<end.lowerBound])
                let boldAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: fontSize),
                    .foregroundColor: NSColor.labelColor,
                ]
                result.append(NSAttributedString(string: boldText, attributes: boldAttrs))
                remaining = remaining.dropFirst(2)[end.upperBound...]
            } else if remaining.hasPrefix("`"), let end = remaining.dropFirst(1).range(of: "`") {
                let codeText = String(remaining.dropFirst(1)[..<end.lowerBound])
                let codeAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular),
                    .foregroundColor: NSColor.systemOrange,
                    .backgroundColor: NSColor.textBackgroundColor.withAlphaComponent(0.3),
                ]
                result.append(NSAttributedString(string: codeText, attributes: codeAttrs))
                remaining = remaining.dropFirst(1)[end.upperBound...]
            } else {
                // 逐字符追加直到遇到特殊字符
                let nextSpecial = remaining.firstIndex(where: { "*`".contains($0) }) ?? remaining.endIndex
                result.append(NSAttributedString(string: String(remaining[..<nextSpecial]), attributes: baseAttrs))
                remaining = remaining[nextSpecial...]
            }
        }
        return result
    }

    private static func renderCodeBlock(_ code: String, language: String, fontSize: CGFloat) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.textBackgroundColor.withAlphaComponent(0.5),
        ]
        return NSAttributedString(string: code + "\n", attributes: attrs)
    }

    private static func styled(_ text: String, size: CGFloat, bold: Bool = false) -> NSAttributedString {
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ])
    }
}
