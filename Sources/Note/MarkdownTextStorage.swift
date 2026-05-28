import AppKit

/// 实时 Markdown 语法高亮 NSTextStorage 子类
/// 每次文本变更后对全文重新应用样式（Note 节点文档通常较短，全量重绘开销可接受）
final class MarkdownTextStorage: NSTextStorage {

    private let backing = NSMutableAttributedString()
    var fontSize: CGFloat = NSFont.systemFontSize

    // MARK: NSTextStorage 必要重写

    override var string: String { backing.string }

    override func attributes(
        at location: Int,
        effectiveRange range: NSRangePointer?
    ) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.utf16.count - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: 样式处理入口（processEditing 在每次编辑后自动调用）

    override func processEditing() {
        applyMarkdownStyles()
        super.processEditing()
    }

    // MARK: - 样式应用

    private func applyMarkdownStyles() {
        let fullRange = NSRange(location: 0, length: backing.length)
        guard fullRange.length > 0 else { return }

        // 先清空为默认样式
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        backing.setAttributes(baseAttrs, range: fullRange)

        let text = backing.string
        let lines = text.components(separatedBy: "\n")
        var offset = 0

        var inCodeBlock = false

        for line in lines {
            let lineLen = (line as NSString).length
            let lineRange = NSRange(location: offset, length: lineLen)

            if line.hasPrefix("```") {
                inCodeBlock.toggle()
                // ``` 行自身用代码色显示
                backing.addAttributes(codeBlockLineAttrs(), range: lineRange)
            } else if inCodeBlock {
                backing.addAttributes(codeBlockAttrs(), range: lineRange)
            } else {
                applyLineStyles(line, lineRange: lineRange)
            }

            // +1 for the "\n"
            offset += lineLen + 1
        }
    }

    private func applyLineStyles(_ line: String, lineRange: NSRange) {
        // 标题
        if line.hasPrefix("### ") {
            applyHeading(level: 3, line: line, lineRange: lineRange)
            return
        } else if line.hasPrefix("## ") {
            applyHeading(level: 2, line: line, lineRange: lineRange)
            return
        } else if line.hasPrefix("# ") {
            applyHeading(level: 1, line: line, lineRange: lineRange)
            return
        }

        // 引用块
        if line.hasPrefix("> ") {
            backing.addAttributes(blockquoteAttrs(), range: lineRange)
            return
        }

        // 水平线
        if line == "---" || line == "===" {
            backing.addAttributes(hrAttrs(), range: lineRange)
            return
        }

        // 内联样式：粗体、斜体、行内代码
        applyInlineStyles(line, lineRange: lineRange)
    }

    // MARK: - 标题

    private func applyHeading(level: Int, line: String, lineRange: NSRange) {
        let (prefixLen, size): (Int, CGFloat) = switch level {
        case 1: (2, fontSize + 8)
        case 2: (3, fontSize + 5)
        default: (4, fontSize + 2)
        }

        // # 前缀变为淡色
        let prefixRange = NSRange(location: lineRange.location, length: prefixLen)
        backing.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .bold),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ], range: prefixRange)

        // 标题文字本体加粗放大
        let textRange = NSRange(
            location: lineRange.location + prefixLen,
            length: max(0, lineRange.length - prefixLen)
        )
        if textRange.length > 0 {
            backing.addAttributes([
                .font: NSFont.boldSystemFont(ofSize: size),
                .foregroundColor: NSColor.labelColor,
            ], range: textRange)
        }
    }

    // MARK: - 内联样式

    private func applyInlineStyles(_ line: String, lineRange: NSRange) {
        let nsLine = line as NSString
        var pos = 0

        while pos < nsLine.length {
            // 粗体 **text**
            if pos + 1 < nsLine.length,
               nsLine.character(at: pos) == UInt16(ascii: "*"),
               nsLine.character(at: pos + 1) == UInt16(ascii: "*") {
                let searchFrom = pos + 2
                if searchFrom < nsLine.length,
                   let closeRange = findClosing("**", in: nsLine, from: searchFrom) {
                    let totalRange = NSRange(
                        location: lineRange.location + pos,
                        length: closeRange.upperBound - pos
                    )
                    backing.addAttributes([
                        .font: NSFont.boldSystemFont(ofSize: fontSize),
                    ], range: totalRange)
                    pos = closeRange.upperBound
                    continue
                }
            }

            // 斜体 *text*（排除 **）
            if nsLine.character(at: pos) == UInt16(ascii: "*") {
                let next = pos + 1
                if next >= nsLine.length || nsLine.character(at: next) != UInt16(ascii: "*") {
                    let searchFrom = pos + 1
                    if searchFrom < nsLine.length,
                       let closeRange = findClosingSingle("*", in: nsLine, from: searchFrom) {
                        let totalRange = NSRange(
                            location: lineRange.location + pos,
                            length: closeRange.upperBound - pos
                        )
                        backing.addAttributes([
                            .font: NSFont(descriptor: NSFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(.italic), size: fontSize) ?? NSFont.systemFont(ofSize: fontSize),
                        ], range: totalRange)
                        pos = closeRange.upperBound
                        continue
                    }
                }
            }

            // 行内代码 `code`
            if nsLine.character(at: pos) == UInt16(ascii: "`") {
                let searchFrom = pos + 1
                if searchFrom < nsLine.length,
                   let closeRange = findClosingSingle("`", in: nsLine, from: searchFrom) {
                    let totalRange = NSRange(
                        location: lineRange.location + pos,
                        length: closeRange.upperBound - pos
                    )
                    backing.addAttributes(inlineCodeAttrs(), range: totalRange)
                    pos = closeRange.upperBound
                    continue
                }
            }

            // 删除线 ~~text~~
            if pos + 1 < nsLine.length,
               nsLine.character(at: pos) == UInt16(ascii: "~"),
               nsLine.character(at: pos + 1) == UInt16(ascii: "~") {
                let searchFrom = pos + 2
                if searchFrom < nsLine.length,
                   let closeRange = findClosing("~~", in: nsLine, from: searchFrom) {
                    let totalRange = NSRange(
                        location: lineRange.location + pos,
                        length: closeRange.upperBound - pos
                    )
                    backing.addAttributes([
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ], range: totalRange)
                    pos = closeRange.upperBound
                    continue
                }
            }

            pos += 1
        }
    }

    // MARK: - 查找闭合标记

    private func findClosing(_ marker: String, in str: NSString, from start: Int) -> Range<Int>? {
        let nsMarker = marker as NSString
        let searchRange = NSRange(location: start, length: str.length - start)
        let found = str.range(of: marker, options: [], range: searchRange)
        guard found.location != NSNotFound else { return nil }
        return start ..< (found.location + nsMarker.length)
    }

    private func findClosingSingle(_ marker: String, in str: NSString, from start: Int) -> Range<Int>? {
        let ch = (marker as NSString).character(at: 0)
        for i in start ..< str.length {
            if str.character(at: i) == ch {
                return start ..< (i + 1)
            }
        }
        return nil
    }

    // MARK: - 样式属性

    private func codeBlockAttrs() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular),
            .foregroundColor: NSColor.systemTeal,
            .backgroundColor: NSColor.textBackgroundColor.withAlphaComponent(0.4),
        ]
    }

    private func codeBlockLineAttrs() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
    }

    private func inlineCodeAttrs() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular),
            .foregroundColor: NSColor.systemOrange,
            .backgroundColor: NSColor.textBackgroundColor.withAlphaComponent(0.3),
        ]
    }

    private func blockquoteAttrs() -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
    }

    private func hrAttrs() -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.separatorColor,
        ]
    }
}

private extension UInt16 {
    init(ascii scalar: Unicode.Scalar) {
        self = UInt16(scalar.value)
    }
}
