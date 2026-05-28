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
        textView.isRichText = false
        textView.allowsUndo = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.delegate = context.coordinator

        // 初始文本写入 backing storage 而非 textView.string（绕过富文本覆盖）
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
        // 只在外部内容真正变化时更新，防止光标跳动
        if textView.string != text {
            let sel = textView.selectedRange()
            ts.replaceCharacters(in: NSRange(location: 0, length: ts.length), with: text)
            let safeRange = NSRange(location: min(sel.location, ts.length), length: 0)
            textView.setSelectedRange(safeRange)
        }
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

        init(parent: MarkdownLiveEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let newText = tv.string
            parent.text = newText
            parent.onChange?(newText)
        }
    }
}
