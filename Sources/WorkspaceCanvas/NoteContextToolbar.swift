import SwiftUI
import AppKit

// MARK: - Note 专属浮动工具栏

struct NoteContextToolbar: View {
    let nodeId: UUID
    let isFormatted: Bool
    let fontSize: Int
    let currentColor: String

    let onBgColor: (String) -> Void
    let onFontSize: (Int) -> Void
    let onConnect: () -> Void
    let onToggleFormatted: () -> Void
    let onDelete: () -> Void
    let onSaveAs: () -> Void
    var connections: [ToolbarConnectionItem] = []
    var onDeleteConnection: (UUID) -> Void = { _ in }

    @State private var showColorPicker = false
    @State private var showFontSizeMenu = false
    @State private var showHeadingPicker = false
    @State private var currentFontSize: Int = 14

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
            headingButton
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
            if !connections.isEmpty {
                ConnectionBadgeButton(connections: connections, onDelete: onDeleteConnection)
            }
            noteButton("m.square",
                       tooltip: isFormatted ? "纯文本" : "格式化",
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
        Button {
            showColorPicker = true
        } label: {
            Circle()
                .fill(NoteColorPickerPopover.colorFromString(currentColor))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color(white: 0.7), lineWidth: 1))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Background Color")
        .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
            NoteColorPickerPopover(selectedColor: currentColor) { color in
                onBgColor(color)
                showColorPicker = false
            }
        }
    }

    private var fontSizeButton: some View {
        ContextToolbarButton(icon: "textformat.size", tooltip: "Font Size") {
            currentFontSize = fontSize
            showFontSizeMenu = true
        }
        .popover(isPresented: $showFontSizeMenu, arrowEdge: .bottom) {
            NoteFontSizePopover(fontSize: $currentFontSize) { size in
                onFontSize(size)
            }
        }
    }

    private var headingButton: some View {
        ContextToolbarButton(icon: "textformat", tooltip: "Heading") {
            showHeadingPicker = true
        }
        .popover(isPresented: $showHeadingPicker, arrowEdge: .bottom) {
            NoteHeadingPickerPopover { level in
                switch level {
                case 1: insertLinePrefix("# ")
                case 2: insertLinePrefix("## ")
                default: insertLinePrefix("### ")
                }
                showHeadingPicker = false
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
    let selectedColor: String
    let onSelect: (String) -> Void

    private let row1: [(name: String, color: Color)] = [
        ("yellow",  Color(red: 0.99, green: 0.97, blue: 0.72)),
        ("pink",    Color(red: 0.96, green: 0.75, blue: 0.80)),
        ("blue",    Color(red: 0.73, green: 0.84, blue: 0.96)),
        ("green",   Color(red: 0.73, green: 0.93, blue: 0.80)),
        ("orange",  Color(red: 0.99, green: 0.84, blue: 0.67)),
        ("purple",  Color(red: 0.87, green: 0.77, blue: 0.96)),
        ("white",   Color(red: 0.97, green: 0.97, blue: 0.97)),
    ]

    private let row2: [(name: String, color: Color)] = [
        ("black",     Color(red: 0.18, green: 0.18, blue: 0.18)),
        ("darkgray",  Color(red: 0.25, green: 0.32, blue: 0.38)),
        ("darkblue",  Color(red: 0.10, green: 0.18, blue: 0.45)),
    ]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(row1, id: \.name) { preset in
                    colorCircle(preset)
                }
            }
            HStack(spacing: 6) {
                ForEach(row2, id: \.name) { preset in
                    colorCircle(preset)
                }
                Spacer()
            }
            Divider()
            Button {
                let panel = NSColorPanel.shared
                panel.showsAlpha = false
                panel.setTarget(nil)
                panel.setAction(nil)
                panel.orderFront(nil)
                NotificationCenter.default.addObserver(
                    forName: NSColorPanel.colorDidChangeNotification,
                    object: panel,
                    queue: .main
                ) { notif in
                    if let p = notif.object as? NSColorPanel {
                        let hex = p.color.hexString
                        onSelect(hex)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 13))
                    Text("note.toolbar.more_colors".localized)
                        .font(.system(size: 13))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(white: 0.95))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(minWidth: 220)
    }

    private func colorCircle(_ preset: (name: String, color: Color)) -> some View {
        Circle()
            .fill(preset.color)
            .frame(width: 28, height: 28)
            .overlay(
                Circle().strokeBorder(
                    selectedColor == preset.name ? Color.accentColor : Color(white: 0.8),
                    lineWidth: selectedColor == preset.name ? 2 : 1
                )
            )
            .onTapGesture { onSelect(preset.name) }
    }

    /// 将颜色字符串（预设名称或 hex）转为 Color
    static func colorFromString(_ str: String) -> Color {
        switch str {
        case "yellow":   return Color(red: 0.99, green: 0.97, blue: 0.72)
        case "pink":     return Color(red: 0.96, green: 0.75, blue: 0.80)
        case "blue":     return Color(red: 0.73, green: 0.84, blue: 0.96)
        case "green":    return Color(red: 0.73, green: 0.93, blue: 0.80)
        case "orange":   return Color(red: 0.99, green: 0.84, blue: 0.67)
        case "purple":   return Color(red: 0.87, green: 0.77, blue: 0.96)
        case "white":    return Color(red: 0.97, green: 0.97, blue: 0.97)
        case "black":    return Color(red: 0.18, green: 0.18, blue: 0.18)
        case "darkgray": return Color(red: 0.25, green: 0.32, blue: 0.38)
        case "darkblue": return Color(red: 0.10, green: 0.18, blue: 0.45)
        default:
            if let nsColor = NSColor(hex: str) {
                return Color(nsColor: nsColor)
            }
            return Color(red: 0.99, green: 0.97, blue: 0.72)
        }
    }
}

// MARK: - 字体大小加减器弹出框

struct NoteFontSizePopover: View {
    @Binding var fontSize: Int
    let onConfirm: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button {
                let newSize = max(10, fontSize - 1)
                fontSize = newSize
                onConfirm(newSize)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("\(fontSize)")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .frame(minWidth: 32, alignment: .center)

            Button {
                let newSize = min(32, fontSize + 1)
                fontSize = newSize
                onConfirm(newSize)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - 标题级别选择弹出框

struct NoteHeadingPickerPopover: View {
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headingRow("# Heading 1",   level: 1, size: 20, weight: .bold)
            headingRow("## Heading 2",  level: 2, size: 16, weight: .semibold)
            headingRow("### Heading 3", level: 3, size: 13, weight: .medium)
        }
        .padding(6)
        .frame(minWidth: 160)
    }

    private func headingRow(_ label: String, level: Int, size: CGFloat, weight: Font.Weight) -> some View {
        Button { onSelect(level) } label: {
            Text(label)
                .font(.system(size: size, weight: weight))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
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
