import AppKit
import OSLog
import SwiftUI

private let noteLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "open-maestri", category: "Note")

// MARK: - Note 编辑器状态（@Observable，避免重建 NSHostingView）

@Observable
final class NoteEditorState {
    var isFormatted: Bool = false
    var content: String = ""
}

// MARK: - Note 节点 NSViewController

/// Note 节点 NSViewController（包裹 NoteEditingView）
final class NoteNodeViewController: NSViewController {
    let noteId: UUID
    let filePath: String
    let editorState = NoteEditorState()

    /// 标题变更回调（首行内容变化时触发，用于更新节点 header）
    var onTitleChanged: ((String) -> Void)?

    private var notificationObserver: NSObjectProtocol?
    private var fileChangeObserver: NSObjectProtocol?

    init(noteId: UUID, filePath: String) {
        self.noteId = noteId
        self.filePath = filePath
        super.init(nibName: nil, bundle: nil)
        editorState.content = (try? NoteFileManager.shared.read(filePath: filePath)) ?? ""
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let editingView = NoteEditingView(
            state: editorState,
            filePath: filePath,
            nodeId: noteId
        ) { [weak self] newContent in
            guard let self else { return }
            do {
                try NoteFileManager.shared.write(filePath: filePath, content: newContent)
            } catch {
                noteLogger.error("Failed to save note: \(error.localizedDescription)")
            }
        } onFirstLineChanged: { [weak self] title in
            self?.onTitleChanged?(title)
        }

        let host = NSHostingView(rootView: editingView)
        self.view = host

        emitInitialTitle()
        observeFormattedToggle()
        observeFileChange()
    }

    deinit {
        if let obs = notificationObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = fileChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - 监听格式化切换通知（来自工具栏）

    private func observeFormattedToggle() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .noteFormattedToggled,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self,
                  let id = notif.userInfo?["nodeId"] as? UUID,
                  id == self.noteId,
                  let isPreviewing = notif.userInfo?["isPreviewing"] as? Bool else { return }
            editorState.isFormatted = isPreviewing
        }
    }

    // MARK: - 监听外部文件写入（CLI 写入时同步 editorState）

    private func observeFileChange() {
        fileChangeObserver = NotificationCenter.default.addObserver(
            forName: .noteFileDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self,
                  let changedPath = notif.userInfo?["filePath"] as? String,
                  changedPath == self.filePath,
                  let newContent = notif.userInfo?["content"] as? String,
                  self.editorState.content != newContent else { return }
            self.editorState.content = newContent
        }
    }

    private func emitInitialTitle() {
        let firstLine = editorState.content
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
