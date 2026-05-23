import SwiftUI

/// Note 节点编辑视图（Raw/Formatted 双视图切换，由外部 NoteEditorState 驱动）
struct NoteEditingView: View {
    @Bindable var state: NoteEditorState
    let filePath: String
    var nodeId: UUID? = nil
    let onSave: (String) -> Void
    var onFirstLineChanged: ((String) -> Void)? = nil

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
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if state.content.isEmpty {
                    Text("note.placeholder")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

/// Markdown 预览（AttributedString 渲染）
struct MarkdownPreviewView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            Text(attributedMarkdown)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
    }

    private var attributedMarkdown: AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }
}
