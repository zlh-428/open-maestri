import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Note ScrollView 注册表

/// 全局注册表：nodeId → NSScrollView（供画布路由滚动事件使用）
final class NoteScrollViewRegistry {
    static let shared = NoteScrollViewRegistry()
    private var scrollViews: [UUID: NSScrollView] = [:]
    private let lock = NSLock()
    private init() {}

    func register(nodeId: UUID, scrollView: NSScrollView) {
        lock.lock(); defer { lock.unlock() }
        scrollViews[nodeId] = scrollView
    }

    func unregister(nodeId: UUID) {
        lock.lock(); defer { lock.unlock() }
        scrollViews.removeValue(forKey: nodeId)
    }

    func scrollView(for nodeId: UUID) -> NSScrollView? {
        lock.lock(); defer { lock.unlock() }
        return scrollViews[nodeId]
    }
}

// MARK: - Note NSTextView 注册表（供工具栏格式化操作使用）

/// 全局注册表：nodeId → NSTextView，工具栏按钮通过此注册表获取 NSTextView 并执行格式化插入
final class NoteTextViewRegistry {
    static let shared = NoteTextViewRegistry()
    private var textViews: [UUID: NSTextView] = [:]
    private let lock = NSLock()
    private init() {}

    func register(nodeId: UUID, textView: NSTextView) {
        lock.lock(); defer { lock.unlock() }
        textViews[nodeId] = textView
    }

    func unregister(nodeId: UUID) {
        lock.lock(); defer { lock.unlock() }
        textViews.removeValue(forKey: nodeId)
    }

    func textView(for nodeId: UUID) -> NSTextView? {
        lock.lock(); defer { lock.unlock() }
        return textViews[nodeId]
    }

    /// 在选中范围插入 markdown 包裹语法（如 **text**）；无选中则插入后将光标置于中间
    @MainActor func insertWrapping(nodeId: UUID, prefix: String, suffix: String) {
        guard let tv = textView(for: nodeId) else { return }
        let range = tv.selectedRange()
        let selectedText = (tv.string as NSString).substring(with: range)
        let replacement = selectedText.isEmpty
            ? "\(prefix)\(suffix)"
            : "\(prefix)\(selectedText)\(suffix)"
        if tv.shouldChangeText(in: range, replacementString: replacement) {
            tv.replaceCharacters(in: range, with: replacement)
            tv.didChangeText()
            if selectedText.isEmpty {
                let cursorPos = range.location + prefix.utf16.count
                tv.setSelectedRange(NSRange(location: cursorPos, length: 0))
            }
        }
    }

    /// 在选中行首插入前缀（标题 # / 列表 - / 待办 - [ ]  等）
    @MainActor func insertLinePrefix(nodeId: UUID, prefix: String) {
        guard let tv = textView(for: nodeId) else { return }
        let str = tv.string as NSString
        let range = tv.selectedRange()
        let lineStart = str.lineRange(for: NSRange(location: range.location, length: 0)).location
        let insertRange = NSRange(location: lineStart, length: 0)
        if tv.shouldChangeText(in: insertRange, replacementString: prefix) {
            tv.replaceCharacters(in: insertRange, with: prefix)
            tv.didChangeText()
        }
    }

    /// 在光标处插入原始文本，并将光标移至末尾
    @MainActor func insertText(nodeId: UUID, text: String, cursorOffset: Int? = nil) {
        guard let tv = textView(for: nodeId) else { return }
        let range = tv.selectedRange()
        if tv.shouldChangeText(in: range, replacementString: text) {
            tv.replaceCharacters(in: range, with: text)
            tv.didChangeText()
            let newPos = range.location + (cursorOffset ?? text.utf16.count)
            tv.setSelectedRange(NSRange(location: newPos, length: 0))
        }
    }
}

// MARK: - 支持粘贴图片的 Note 文本编辑器

/// AppKit 包装的文本编辑器，支持从剪贴板粘贴图片
/// 图片以 PNG 格式保存至 `imagesDir`，并以 `![filename](relative_path)` 语法插入
struct NoteImagePasteTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// Note 所在目录（图片存储子目录 `images/` 位于此目录下）
    let noteFilePath: String
    /// 节点 ID（用于注册 ScrollView 到全局注册表）
    var nodeId: UUID? = nil
    /// 内容变化回调
    var onChange: ((String) -> Void)? = nil
    /// 首行变化回调
    var onFirstLineChanged: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.string = text
        // 设置 coordinator 弱引用到 textView
        context.coordinator.textView = textView
        // 注册 ScrollView 到全局注册表（供画布路由滚动事件）
        if let nodeId {
            NoteScrollViewRegistry.shared.register(nodeId: nodeId, scrollView: scrollView)
            NoteTextViewRegistry.shared.register(nodeId: nodeId, textView: textView)
        }
        return scrollView
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if let nodeId = coordinator.parent.nodeId {
            NoteScrollViewRegistry.shared.unregister(nodeId: nodeId)
            NoteTextViewRegistry.shared.unregister(nodeId: nodeId)
        }
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // 只在外部变化时更新，防止光标跳动
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            // 恢复合理的光标位置
            let safeRange = NSRange(location: min(selected.location, textView.string.utf16.count), length: 0)
            textView.setSelectedRange(safeRange)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteImagePasteTextEditor
        weak var textView: NSTextView?

        init(parent: NoteImagePasteTextEditor) {
            self.parent = parent
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            parent.text = newText
            parent.onChange?(newText)
            // 首行标题
            emitFirstLine(newText)
        }

        // MARK: - 粘贴拦截

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSText.paste(_:)) {
                return handlePaste(in: textView)
            }
            return false
        }

        // MARK: - 图片粘贴处理

        private func handlePaste(in textView: NSTextView) -> Bool {
            let pasteboard = NSPasteboard.general
            // 优先检查图片
            if pasteboard.canReadItem(withDataConformingToTypes: [UTType.image.identifier, UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier]) {
                if let image = NSImage(pasteboard: pasteboard) {
                    insertImage(image, into: textView)
                    return true
                }
            }
            // 其他类型走默认粘贴
            return false
        }

        private func insertImage(_ image: NSImage, into textView: NSTextView) {
            // 生成唯一文件名
            let filename = "image-\(UUID().uuidString.prefix(8)).png"
            let noteDir = URL(fileURLWithPath: parent.noteFilePath).deletingLastPathComponent()
            let imagesDir = noteDir.appendingPathComponent("images")

            do {
                try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
                let imageURL = imagesDir.appendingPathComponent(filename)

                // 导出为 PNG
                guard let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let pngData = bitmap.representation(using: .png, properties: [:]) else {
                    return
                }
                try pngData.write(to: imageURL)

                // 插入 Markdown 语法（相对路径）
                let relPath = "images/\(filename)"
                let markdownSnippet = "![\(filename)](\(relPath))"

                let range = textView.selectedRange()
                if textView.shouldChangeText(in: range, replacementString: markdownSnippet) {
                    textView.replaceCharacters(in: range, with: markdownSnippet)
                    textView.didChangeText()
                }
            } catch {
                // 插入失败时降级为默认粘贴
                textView.paste(nil)
            }
        }

        // MARK: - 首行标题提取

        private func emitFirstLine(_ text: String) {
            let firstLine = text
                .components(separatedBy: "\n")
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                ?? ""
            let title = firstLine
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .trimmingCharacters(in: .whitespaces)
            if !title.isEmpty {
                parent.onFirstLineChanged?(title)
            }
        }
    }
}
