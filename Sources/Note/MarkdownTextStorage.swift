import AppKit

/// Typora 风格实时 Markdown 渲染 NSTextStorage
///
/// 渲染策略：
/// - 光标所在行：显示原始 Markdown 符号（可编辑），同时应用样式
/// - 其他行：隐藏语法符号（字体缩至 0.01pt + 透明），仅呈现渲染效果
final class MarkdownTextStorage: NSTextStorage {

    private let backing = NSMutableAttributedString()
    var fontSize: CGFloat = NSFont.systemFontSize

    /// 当前光标所在行号（-1 表示无焦点）
    /// 由 MarkdownLiveEditor Coordinator 在选区变化时调用 updateCursorLine() 更新
    private(set) var cursorLineIndex: Int = -1

    /// 更新光标行并刷新样式，必须在 NSTextStorage 编辑事务之外调用
    func updateCursorLine(_ lineIndex: Int) {
        guard lineIndex != cursorLineIndex else { return }
        cursorLineIndex = lineIndex
        guard backing.length > 0 else { return }
        // 直接重新排版，不走 beginEditing/endEditing（避免重入）
        let fullRange = NSRange(location: 0, length: backing.length)
        applyMarkdownStyles()
        // 通知所有 layoutManager 重新布局
        for lm in layoutManagers {
            lm.processEditing(for: self,
                              edited: .editedAttributes,
                              range: fullRange,
                              changeInLength: 0,
                              invalidatedRange: fullRange)
        }
    }

    // MARK: - NSTextStorage 必要重写

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

    // processEditing 在每次 endEditing 后由系统自动调用
    override func processEditing() {
        applyMarkdownStyles()
        super.processEditing()
    }

    // MARK: - 全文样式应用（直接操作 backing，不走 setAttributes 包裹，避免递归）

    private func applyMarkdownStyles() {
        let fullRange = NSRange(location: 0, length: backing.length)
        guard fullRange.length > 0 else { return }

        backing.setAttributes([
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.labelColor,
        ], range: fullRange)

        let text = backing.string
        let lines = text.components(separatedBy: "\n")
        var offset = 0
        var inCodeBlock = false
        var codeBlockStartLine = -1

        for (lineIdx, line) in lines.enumerated() {
            let lineLen = (line as NSString).length
            let lineRange = NSRange(location: offset, length: lineLen)
            let isCursorLine = (lineIdx == cursorLineIndex)

            if line.hasPrefix("```") {
                if inCodeBlock {
                    let blockStart = offsetForLine(codeBlockStartLine, in: lines)
                    let blockEnd = offset + lineLen
                    let blockRange = NSRange(location: blockStart, length: blockEnd - blockStart)
                    applyCodeBlock(range: blockRange,
                                   blockStartLine: codeBlockStartLine,
                                   blockEndLine: lineIdx,
                                   lines: lines)
                    inCodeBlock = false
                    codeBlockStartLine = -1
                } else {
                    inCodeBlock = true
                    codeBlockStartLine = lineIdx
                }
                offset += lineLen + 1
                continue
            }

            if inCodeBlock {
                offset += lineLen + 1
                continue
            }

            applyLineStyles(line, lineRange: lineRange, isCursorLine: isCursorLine)
            offset += lineLen + 1
        }

        // 未关闭的代码块
        if inCodeBlock {
            let blockStart = offsetForLine(codeBlockStartLine, in: lines)
            let blockRange = NSRange(location: blockStart, length: max(0, backing.length - blockStart))
            applyCodeBlock(range: blockRange,
                           blockStartLine: codeBlockStartLine,
                           blockEndLine: lines.count - 1,
                           lines: lines)
        }
    }

    // MARK: - 行级样式

    private func applyLineStyles(_ line: String, lineRange: NSRange, isCursorLine: Bool) {
        if line.hasPrefix("### ") {
            applyHeading(level: 3, line: line, lineRange: lineRange, isCursorLine: isCursorLine)
        } else if line.hasPrefix("## ") {
            applyHeading(level: 2, line: line, lineRange: lineRange, isCursorLine: isCursorLine)
        } else if line.hasPrefix("# ") {
            applyHeading(level: 1, line: line, lineRange: lineRange, isCursorLine: isCursorLine)
        } else if line.hasPrefix("> ") {
            applyBlockquote(line: line, lineRange: lineRange, isCursorLine: isCursorLine)
        } else if line == "---" || line == "===" {
            backing.addAttributes([.foregroundColor: NSColor.separatorColor], range: lineRange)
        } else {
            applyInlineStyles(line, lineRange: lineRange, isCursorLine: isCursorLine)
        }
    }

    // MARK: - 标题

    private func applyHeading(level: Int, line: String, lineRange: NSRange, isCursorLine: Bool) {
        let (prefixLen, size): (Int, CGFloat) = switch level {
        case 1: (2, fontSize + 10)
        case 2: (3, fontSize + 6)
        default: (4, fontSize + 3)
        }
        let prefixRange = NSRange(location: lineRange.location, length: min(prefixLen, lineRange.length))
        let textLen = max(0, lineRange.length - prefixLen)
        let textRange = NSRange(location: lineRange.location + prefixLen, length: textLen)

        if isCursorLine {
            backing.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: size, weight: .bold),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ], range: prefixRange)
        } else {
            backing.addAttributes(hidden(size: size), range: prefixRange)
        }
        if textLen > 0 {
            backing.addAttributes([
                .font: NSFont.boldSystemFont(ofSize: size),
                .foregroundColor: NSColor.labelColor,
            ], range: textRange)
        }
    }

    // MARK: - 引用块

    private func applyBlockquote(line: String, lineRange: NSRange, isCursorLine: Bool) {
        let prefixRange = NSRange(location: lineRange.location, length: min(2, lineRange.length))
        let textLen = max(0, lineRange.length - 2)
        let textRange = NSRange(location: lineRange.location + 2, length: textLen)
        if isCursorLine {
            backing.addAttributes([.foregroundColor: NSColor.tertiaryLabelColor], range: prefixRange)
        } else {
            backing.addAttributes(hidden(size: fontSize), range: prefixRange)
        }
        if textLen > 0 {
            backing.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: fontSize),
            ], range: textRange)
        }
    }

    // MARK: - 代码块

    private func applyCodeBlock(
        range: NSRange,
        blockStartLine: Int,
        blockEndLine: Int,
        lines: [String]
    ) {
        backing.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular),
            .foregroundColor: NSColor.systemTeal,
        ], range: range)

        var off = offsetForLine(blockStartLine, in: lines)
        for i in blockStartLine ... blockEndLine {
            let l = lines[i]
            let lLen = (l as NSString).length
            let lRange = NSRange(location: off, length: lLen)
            if (i == blockStartLine || i == blockEndLine) && i != cursorLineIndex {
                backing.addAttributes(hidden(size: fontSize - 1), range: lRange)
            }
            off += lLen + 1
        }
    }

    // MARK: - 内联样式

    private func applyInlineStyles(_ line: String, lineRange: NSRange, isCursorLine: Bool) {
        let nsLine = line as NSString
        var pos = 0

        while pos < nsLine.length {
            // 粗体 **text**
            if pos + 1 < nsLine.length,
               nsLine.character(at: pos) == 42, nsLine.character(at: pos + 1) == 42 {
                let from = pos + 2
                if from < nsLine.length, let close = findClosing("**", in: nsLine, from: from) {
                    applyWrap(lineRange: lineRange, pos: pos, close: close,
                              markerLen: 2, isCursorLine: isCursorLine,
                              innerAttrs: [.font: NSFont.boldSystemFont(ofSize: fontSize)])
                    pos = close.upperBound; continue
                }
            }

            // 斜체 *text*（排除 **）
            if nsLine.character(at: pos) == 42 {
                let next = pos + 1
                if next >= nsLine.length || nsLine.character(at: next) != 42 {
                    if let close = findClosingSingle("*", in: nsLine, from: pos + 1) {
                        let italicFont = NSFont(
                            descriptor: NSFont.systemFont(ofSize: fontSize)
                                .fontDescriptor.withSymbolicTraits(.italic),
                            size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
                        applyWrap(lineRange: lineRange, pos: pos, close: close,
                                  markerLen: 1, isCursorLine: isCursorLine,
                                  innerAttrs: [.font: italicFont])
                        pos = close.upperBound; continue
                    }
                }
            }

            // 删除线 ~~text~~
            if pos + 1 < nsLine.length,
               nsLine.character(at: pos) == 126, nsLine.character(at: pos + 1) == 126 {
                let from = pos + 2
                if from < nsLine.length, let close = findClosing("~~", in: nsLine, from: from) {
                    applyWrap(lineRange: lineRange, pos: pos, close: close,
                              markerLen: 2, isCursorLine: isCursorLine,
                              innerAttrs: [
                                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                .foregroundColor: NSColor.secondaryLabelColor,
                              ])
                    pos = close.upperBound; continue
                }
            }

            // 行内代码 `code`
            if nsLine.character(at: pos) == 96 {
                if let close = findClosingSingle("`", in: nsLine, from: pos + 1) {
                    let codeFont = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
                    applyWrap(lineRange: lineRange, pos: pos, close: close,
                              markerLen: 1, isCursorLine: isCursorLine,
                              innerAttrs: [
                                .font: codeFont,
                                .foregroundColor: NSColor.systemOrange,
                                .backgroundColor: NSColor.textBackgroundColor.withAlphaComponent(0.3),
                              ])
                    pos = close.upperBound; continue
                }
            }

            pos += 1
        }
    }

    /// 统一处理"标记包裹"的样式应用
    private func applyWrap(
        lineRange: NSRange,
        pos: Int,
        close: Range<Int>,
        markerLen: Int,
        isCursorLine: Bool,
        innerAttrs: [NSAttributedString.Key: Any]
    ) {
        let absPos = lineRange.location + pos
        let openRange  = NSRange(location: absPos, length: markerLen)
        let innerLen   = close.upperBound - pos - markerLen * 2
        let innerRange = NSRange(location: absPos + markerLen, length: max(0, innerLen))
        let closeRange = NSRange(location: absPos + markerLen + max(0, innerLen), length: markerLen)

        if isCursorLine {
            backing.addAttributes([.foregroundColor: NSColor.tertiaryLabelColor], range: openRange)
            if innerRange.length > 0 { backing.addAttributes(innerAttrs, range: innerRange) }
            backing.addAttributes([.foregroundColor: NSColor.tertiaryLabelColor], range: closeRange)
        } else {
            backing.addAttributes(hidden(size: fontSize), range: openRange)
            if innerRange.length > 0 { backing.addAttributes(innerAttrs, range: innerRange) }
            backing.addAttributes(hidden(size: fontSize), range: closeRange)
        }
    }

    // MARK: - 工具方法

    private func hidden(size: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 0.01),
            .foregroundColor: NSColor.clear,
        ]
    }

    private func offsetForLine(_ lineIdx: Int, in lines: [String]) -> Int {
        var off = 0
        for i in 0 ..< lineIdx {
            off += (lines[i] as NSString).length + 1
        }
        return off
    }

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
            if str.character(at: i) == ch { return start ..< (i + 1) }
        }
        return nil
    }
}
