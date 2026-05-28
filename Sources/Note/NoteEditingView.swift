import SwiftUI

/// Note 节点编辑视图（Raw/Formatted 双视图切换，由外部 NoteEditorState 驱动）
struct NoteEditingView: View {
    @Bindable var state: NoteEditorState
    let filePath: String
    var nodeId: UUID? = nil
    let onSave: (String) -> Void
    var onFirstLineChanged: ((String) -> Void)? = nil

    @State private var isFocused = false

    var body: some View {
        if state.isFormatted {
            MarkdownPreviewView(markdown: state.content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack(alignment: .topLeading) {
                NoteImagePasteTextEditor(
                    text: $state.content,
                    noteFilePath: filePath,
                    nodeId: nodeId,
                    onChange: { newValue in
                        onSave(newValue)
                    },
                    onFirstLineChanged: { title in
                        onFirstLineChanged?(title)
                    },
                    onFocusChanged: { focused in
                        isFocused = focused
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if state.content.isEmpty && !isFocused {
                    Text("note.placeholder")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

/// Markdown 预览（使用 MarkdownRenderer 渲染，保留所有换行）
struct MarkdownPreviewView: View {
    let markdown: String
    var fontSize: CGFloat = 14

    var body: some View {
        MarkdownPreviewNSView(markdown: markdown, fontSize: fontSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MarkdownPreviewNSView: NSViewRepresentable {
    let markdown: String
    let fontSize: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let tv = scrollView.documentView as? NSTextView else { return scrollView }
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = true
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 4, height: 8)
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = CGSize(
            width: scrollView.frame.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        let attributed = MarkdownRenderer.render(markdown, fontSize: fontSize)
        tv.textStorage?.setAttributedString(attributed)
    }
}
