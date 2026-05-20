import SwiftUI

/// Note 节点编辑视图（Raw/Formatted 双视图切换）
struct NoteEditingView: View {
    @State private var isFormatted: Bool = false
    @Binding var content: String
    let filePath: String
    /// 节点 ID（传递给 NoteImagePasteTextEditor 用于注册 ScrollView）
    var nodeId: UUID? = nil
    let onSave: (String) -> Void
    /// 首行文本变化时回调（用于自动更新节点标题）
    var onFirstLineChanged: ((String) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 上下文工具栏
            HStack(spacing: 8) {
                Toggle(isOn: $isFormatted) {
                    Label(isFormatted ? "note.preview".localized : "note.edit".localized,
                          systemImage: isFormatted ? "eye" : "pencil")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if isFormatted {
                MarkdownPreviewView(markdown: content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .topLeading) {
                    // 使用支持粘贴图片的 NSTextView 包装器
                    NoteImagePasteTextEditor(
                        text: $content,
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

                    if content.isEmpty {
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
