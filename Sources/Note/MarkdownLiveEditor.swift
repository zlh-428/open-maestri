import AppKit
import SwiftUI

/// 可编辑、实时渲染 Markdown 样式的编辑器
/// 使用 MarkdownTextStorage 实现输入时即时高亮，内容通过 Binding<String> 双向同步
struct MarkdownLiveEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = NSFont.systemFontSize
    var nodeId: UUID? = nil
    var onChange: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = MarkdownTextStorage()
        textStorage.fontSize = fontSize

        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(containerSize: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        // isRichText 不能设为 false：自定义 NSTextStorage 会设置富文本属性，
        // false 会导致 NSTextView 拒绝处理带属性的字符串，造成输入失效
        textView.allowsUndo = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.delegate = context.coordinator

        if !text.isEmpty {
            textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        context.coordinator.textView = textView
        context.coordinator.textStorage = textStorage

        if let nodeId {
            NoteScrollViewRegistry.shared.register(nodeId: nodeId, scrollView: scrollView)
            NoteTextViewRegistry.shared.register(nodeId: nodeId, textView: textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              let ts = textView.textStorage as? MarkdownTextStorage else { return }
        ts.fontSize = fontSize
        // 只响应外部（CLI/文件同步）写入，忽略用户自己输入触发的回调
        guard !context.coordinator.isEditing, textView.string != text else { return }
        let sel = textView.selectedRange()
        ts.replaceCharacters(in: NSRange(location: 0, length: ts.length), with: text)
        let safeRange = NSRange(location: min(sel.location, ts.length), length: 0)
        textView.setSelectedRange(safeRange)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if let nodeId = coordinator.parent.nodeId {
            NoteScrollViewRegistry.shared.unregister(nodeId: nodeId)
            NoteTextViewRegistry.shared.unregister(nodeId: nodeId)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownLiveEditor
        weak var textView: NSTextView?
        weak var textStorage: MarkdownTextStorage?
        /// 用户正在输入时为 true，阻止 updateNSView 干扰
        var isEditing = false

        init(parent: MarkdownLiveEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            textStorage?.cursorLineIndex = -1
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let newText = tv.string
            updateCursorLine(in: tv)
            parent.text = newText
            parent.onChange?(newText)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            updateCursorLine(in: tv)
        }

        private func updateCursorLine(in tv: NSTextView) {
            let pos = tv.selectedRange().location
            let str = tv.string as NSString
            let lineRange = str.lineRange(for: NSRange(location: min(pos, max(0, str.length - 1)), length: 0))
            let prefix = str.substring(to: lineRange.location)
            let line = prefix.components(separatedBy: "\n").count - 1
            textStorage?.cursorLineIndex = line
        }
    }
}
