import AppKit
import OSLog
import SwiftUI

private let noteLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "open-maestri", category: "Note")

// MARK: - Note 编辑器状态（@Observable，避免重建 NSHostingView）

@Observable
final class NoteEditorState {
    var isFormatted: Bool = false
    var content: String = ""
    /// 模式切换后需要恢复焦点的标志，由 NSViewRepresentable.updateNSView 消费并清除
    var pendingFocusRestore: Bool = false
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

    // MARK: - 防抖写入状态

    /// 当前待写入的内容（nil 表示无待刷新内容）
    private var pendingSaveContent: String?
    /// 防抖任务句柄，取消后重建以重置 300ms 计时
    private var debounceTask: Task<Void, Never>?

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
            self?.scheduleSave(content: newContent)
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
        // 视图销毁时将内存缓存立即写入磁盘（后台执行，不阻塞主线程）
        debounceTask?.cancel()
        if let content = pendingSaveContent {
            let fp = filePath
            DispatchQueue.global(qos: .utility).async {
                try? NoteFileManager.shared.write(filePath: fp, content: content)
            }
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
            editorState.pendingFocusRestore = true
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

    // MARK: - 防抖磁盘写入

    /// 防抖保存：缓存最新内容，300ms 无新输入后在后台线程写盘。
    /// 主线程调用（NSTextViewDelegate 回调保证在主线程）。
    private func scheduleSave(content: String) {
        pendingSaveContent = content
        // 重置计时器
        debounceTask?.cancel()
        let fp = filePath
        debounceTask = Task.detached { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                // 被取消：等待下次 scheduleSave 或 flushPendingSave
                return
            }
            // ── 此处已脱离主线程，在协作线程池上执行同步 I/O ──
            try? NoteFileManager.shared.write(filePath: fp, content: content)
            // 清理状态（回主线程）
            await MainActor.run { [weak self] in
                self?.pendingSaveContent = nil
                self?.debounceTask = nil
            }
        }
    }

    /// 立即将待写内容刷新到磁盘（视图隐藏时调用）。
    /// 取消防抖任务，后台异步写入，不阻塞调用线程。
    func flushPendingSave() {
        debounceTask?.cancel()
        debounceTask = nil
        guard let content = pendingSaveContent else { return }
        pendingSaveContent = nil
        let fp = filePath
        Task.detached {
            try? NoteFileManager.shared.write(filePath: fp, content: content)
        }
    }
}
