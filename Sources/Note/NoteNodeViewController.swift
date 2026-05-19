import AppKit
import SwiftUI

/// Note 节点 NSViewController（包裹 NoteEditingView）
final class NoteNodeViewController: NSViewController {
    let noteId: UUID
    let filePath: String
    private var content: String = ""

    /// 标题变更回调（首行内容变化时触发，用于更新节点 header）
    var onTitleChanged: ((String) -> Void)?

    init(noteId: UUID, filePath: String) {
        self.noteId = noteId
        self.filePath = filePath
        super.init(nibName: nil, bundle: nil)
        self.content = (try? NoteFileManager.shared.read(filePath: filePath)) ?? ""
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let binding = Binding(get: { self.content }, set: { self.content = $0 })
        var editingView = NoteEditingView(content: binding, filePath: filePath, nodeId: noteId) { [weak self] newContent in
            guard let self else { return }
            try? NoteFileManager.shared.write(filePath: filePath, content: newContent)
        }
        editingView.onFirstLineChanged = { [weak self] title in
            self?.onTitleChanged?(title)
        }
        let host = NSHostingView(rootView: editingView)
        self.view = host

        // 初始化时主动触发首行标题（onChange 不会在初始加载时触发）
        emitInitialTitle()
    }

    private func emitInitialTitle() {
        let firstLine = content
            .components(separatedBy: "\n")
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            ?? ""
        let title = firstLine
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            onTitleChanged?(title)
        }
    }
}
