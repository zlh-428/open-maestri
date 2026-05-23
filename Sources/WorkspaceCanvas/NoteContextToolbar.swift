import SwiftUI
import AppKit

// MARK: - Note 专属浮动工具栏

struct NoteContextToolbar: View {
    let nodeId: UUID
    let isFormatted: Bool

    let onBgColor: (String) -> Void
    let onFontSize: (Int) -> Void
    let onConnect: () -> Void
    let onToggleFormatted: () -> Void
    let onDelete: () -> Void
    let onSaveAs: () -> Void

    @State private var showColorPicker = false
    @State private var showFontSizeMenu = false

    var body: some View {
        HStack(spacing: 2) {
            // 组1：外观
            colorButton
            fontSizeButton

            toolbarSeparator

            // 组2：内联格式
            noteButton("bold",        tooltip: "Bold")         { insertWrapping("**", "**") }
            noteButton("italic",      tooltip: "Italic")       { insertWrapping("*",  "*") }
            noteButton("strikethrough", tooltip: "Strikethrough") { insertWrapping("~~", "~~") }
            noteButton("chevron.left.forwardslash.chevron.right",
                       tooltip: "Inline Code")                 { insertWrapping("`", "`") }

            toolbarSeparator

            // 组3：块级格式
            noteButton("textformat",  tooltip: "Heading")      { cycleHeading() }
            noteButton("checklist",   tooltip: "Task Item")    { insertLinePrefix("- [ ] ") }
            noteButton("list.bullet", tooltip: "List Item")    { insertLinePrefix("- ") }
            noteButton("curlybraces", tooltip: "Code Block")   { insertCodeBlock() }

            toolbarSeparator

            // 组4：媒体 & 操作
            noteButton("photo",              tooltip: "Insert Image") { insertImage() }
            noteButton("doc.on.doc",         tooltip: "Copy All")    { copyAll() }
            noteButton("square.and.arrow.down", tooltip: "Save As")  { onSaveAs() }

            toolbarSeparator

            // 组5：节点操作
            noteButton("arrow.trianglehead.branch", tooltip: "Connect") { onConnect() }
            noteButton("character.textbox",
                       tooltip: isFormatted ? "Edit Mode" : "Preview Mode",
                       isActive: isFormatted)                           { onToggleFormatted() }
            noteButton("trash", tooltip: "Delete", isDestructive: true) { onDelete() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(white: 0.9), lineWidth: 0.5)
        )
    }

    // MARK: - 子视图

    private var toolbarSeparator: some View {
        Rectangle()
            .fill(Color(white: 0.88))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 3)
    }

    private var colorButton: some View {
        ContextToolbarButton(icon: "circle.fill", tooltip: "Background Color") {
            showColorPicker = true
        }
        .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
            NoteColorPickerPopover { color in
                onBgColor(color)
                showColorPicker = false
            }
        }
    }

    private var fontSizeButton: some View {
        ContextToolbarButton(icon: "textformat.size", tooltip: "Font Size") {
            showFontSizeMenu = true
        }
        .popover(isPresented: $showFontSizeMenu, arrowEdge: .bottom) {
            NoteFontSizePopover { size in
                onFontSize(size)
                showFontSizeMenu = false
            }
        }
    }

    @ViewBuilder
    private func noteButton(
        _ icon: String,
        tooltip: String,
        isActive: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        NoteToolbarButton(
            icon: icon,
            tooltip: tooltip,
            isActive: isActive,
            isDestructive: isDestructive,
            action: action
        )
    }

    // MARK: - 格式化操作（委托给 NoteTextViewRegistry）

    private func insertWrapping(_ prefix: String, _ suffix: String) {
        NoteTextViewRegistry.shared.insertWrapping(nodeId: nodeId, prefix: prefix, suffix: suffix)
    }

    private func insertLinePrefix(_ prefix: String) {
        NoteTextViewRegistry.shared.insertLinePrefix(nodeId: nodeId, prefix: prefix)
    }

    private func insertCodeBlock() {
        // 插入代码块并将光标定位到中间空行
        let text = "```\n\n```"
        NoteTextViewRegistry.shared.insertText(nodeId: nodeId, text: text, cursorOffset: 4)
    }

    @MainActor private func cycleHeading() {
        guard let tv = NoteTextViewRegistry.shared.textView(for: nodeId) else { return }
        let str = tv.string as NSString
        let range = tv.selectedRange()
        let lineRange = str.lineRange(for: NSRange(location: range.location, length: 0))
        let originalLine = str.substring(with: lineRange)
        let trimmed = originalLine.trimmingCharacters(in: .newlines)
        let hasTrailingNewline = originalLine.hasSuffix("\n") || originalLine.hasSuffix("\r\n")

        let stripped: String
        let nextPrefix: String
        if trimmed.hasPrefix("### ") {
            stripped = String(trimmed.dropFirst(4)); nextPrefix = ""
        } else if trimmed.hasPrefix("## ") {
            stripped = String(trimmed.dropFirst(3)); nextPrefix = "### "
        } else if trimmed.hasPrefix("# ") {
            stripped = String(trimmed.dropFirst(2)); nextPrefix = "## "
        } else {
            stripped = trimmed; nextPrefix = "# "
        }

        let newline = hasTrailingNewline ? "\n" : ""
        let newLine = nextPrefix.isEmpty ? "\(stripped)\(newline)" : "\(nextPrefix)\(stripped)\(newline)"
        if tv.shouldChangeText(in: lineRange, replacementString: newLine) {
            tv.replaceCharacters(in: lineRange, with: newLine)
            tv.didChangeText()
        }
    }

    private func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { [nodeId] response in
            guard response == .OK, let url = panel.url else { return }
            // 将图片复制到 Note 的 images/ 子目录，保持相对路径（与粘贴逻辑一致）
            Task { @MainActor in
                guard let tv = NoteTextViewRegistry.shared.textView(for: nodeId) else { return }
                // 从注册表中找到 note 文件路径（通过 NoteScrollViewRegistry 的关联视图）
                // 无法直接拿到 filePath，退而使用文件名+绝对路径（可在后续版本优化为复制到相对目录）
                let filename = url.lastPathComponent
                let snippet = "![\(filename)](\(url.path))"
                let range = tv.selectedRange()
                if tv.shouldChangeText(in: range, replacementString: snippet) {
                    tv.replaceCharacters(in: range, with: snippet)
                    tv.didChangeText()
                }
            }
        }
    }

    @MainActor private func copyAll() {
        guard let tv = NoteTextViewRegistry.shared.textView(for: nodeId) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tv.string, forType: .string)
    }
}

// MARK: - 颜色选择弹出框

struct NoteColorPickerPopover: View {
    let onSelect: (String) -> Void

    private let presets: [(name: String, color: Color)] = [
        ("yellow", .yellow),
        ("pink",   .pink),
        ("green",  .green),
        ("blue",   .blue),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.name) { preset in
                Circle()
                    .fill(preset.color)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(Color(white: 0.8), lineWidth: 1))
                    .onTapGesture { onSelect(preset.name) }
            }
        }
        .padding(12)
    }
}

// MARK: - 字体大小弹出框

struct NoteFontSizePopover: View {
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            fontSizeRow("Small",  size: 12)
            fontSizeRow("Medium", size: 14)
            fontSizeRow("Large",  size: 18)
        }
        .padding(6)
        .frame(minWidth: 100)
    }

    private func fontSizeRow(_ label: String, size: Int) -> some View {
        Button { onSelect(size) } label: {
            Text(label)
                .font(.system(size: CGFloat(size)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Note 工具栏按钮（支持 active / destructive 状态）

struct NoteToolbarButton: View {
    let icon: String
    let tooltip: String
    var isActive: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(iconColor)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(backgroundFill)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            HoverTrackingView { hovering in
                isHovered = hovering
                if hovering {
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        guard !Task.isCancelled else { return }
                        showTooltip = true
                    }
                } else {
                    hoverTask?.cancel()
                    showTooltip = false
                }
            }
        )
        .overlay(alignment: .bottom) {
            if showTooltip {
                Text(tooltip)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color(white: 0.88), lineWidth: 0.5)
                    )
                    .fixedSize()
                    .offset(y: 36)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                    .zIndex(1000)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showTooltip)
    }

    private var iconColor: Color {
        if isDestructive && isHovered { return .red }
        if isActive { return .accentColor }
        return isHovered ? Color(white: 0.15) : Color(white: 0.35)
    }

    private var backgroundFill: Color {
        if isDestructive && isHovered { return .red.opacity(0.08) }
        if isActive { return .accentColor.opacity(0.12) }
        return isHovered ? Color.black.opacity(0.05) : Color.clear
    }
}
