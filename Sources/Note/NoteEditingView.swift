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
            MarkdownLiveEditor(
                text: $state.content,
                nodeId: nodeId,
                onChange: { newValue in
                    onSave(newValue)
                }
            )
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
