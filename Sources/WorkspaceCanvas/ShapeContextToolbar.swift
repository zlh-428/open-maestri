import SwiftUI
import AppKit

// MARK: - Shape 专属浮动工具栏

struct ShapeContextToolbar: View {
    let nodeId: UUID
    let content: ShapeContent
    let onContentChange: (ShapeContent) -> Void
    let onDelete: () -> Void

    @State private var showThemeColorPicker = false
    @State private var showStrokeStylePicker = false
    @State private var showFillStylePicker = false
    @State private var isDeleteHovered = false

    /// 主题色（边框和填充共用同一颜色来源）
    private var themeColor: Color {
        NoteColorPickerPopover.colorFromString(content.strokeColor)
    }

    var body: some View {
        HStack(spacing: 2) {
            themeColorButton
            strokeWidthStepper

            toolbarSeparator

            strokeStyleButton

            toolbarSeparator

            fillStyleButton

            toolbarSeparator

            fontSizeStepper

            toolbarSeparator

            deleteButton
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

    // MARK: - 主题色（边框 + 填充同步）

    private var themeColorButton: some View {
        Button {
            showThemeColorPicker = true
        } label: {
            Circle()
                .fill(themeColor)
                .frame(width: 18, height: 18)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Theme Color")
        .popover(isPresented: $showThemeColorPicker, arrowEdge: .bottom) {
            NoteColorPickerPopover(selectedColor: content.strokeColor) { color in
                var updated = content
                updated.strokeColor = color
                updated.fillColor = color
                onContentChange(updated)
                showThemeColorPicker = false
            }
        }
    }

    // MARK: - 边框粗细步进器

    private var strokeWidthStepper: some View {
        HStack(spacing: 2) {
            Button {
                var updated = content
                updated.strokeWidth = max(1, content.strokeWidth - 1)
                onContentChange(updated)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("\(Int(content.strokeWidth))pt")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(minWidth: 30, alignment: .center)

            Button {
                var updated = content
                updated.strokeWidth = min(20, content.strokeWidth + 1)
                onContentChange(updated)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 边框风格

    private var strokeStyleButton: some View {
        Button {
            showStrokeStylePicker = true
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(white: 0.3))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Stroke Style")
        .popover(isPresented: $showStrokeStylePicker, arrowEdge: .bottom) {
            ShapeStrokeStylePopover(selected: content.strokeStyle) { style in
                var updated = content
                updated.strokeStyle = style
                onContentChange(updated)
                showStrokeStylePicker = false
            }
        }
    }

    // MARK: - 填充风格

    private var fillStyleButton: some View {
        Button {
            showFillStylePicker = true
        } label: {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(white: 0.3))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Fill Style")
        .popover(isPresented: $showFillStylePicker, arrowEdge: .bottom) {
            ShapeFillStylePopover(selected: content.fillStyle) { style in
                var updated = content
                updated.fillStyle = style
                onContentChange(updated)
                showFillStylePicker = false
            }
        }
    }

    // MARK: - 字体大小步进器

    private var fontSizeStepper: some View {
        HStack(spacing: 2) {
            Text("shape.toolbar.font_size".localized)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button {
                var updated = content
                updated.fontSize = max(8, content.fontSize - 1)
                onContentChange(updated)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("\(Int(content.fontSize))pt")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(minWidth: 30, alignment: .center)

            Button {
                var updated = content
                updated.fontSize = min(72, content.fontSize + 1)
                onContentChange(updated)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 删除

    private var deleteButton: some View {
        Button { onDelete() } label: {
            Image(systemName: "trash")
                .font(.system(size: 13))
                .foregroundStyle(isDeleteHovered ? .red : Color(white: 0.35))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isDeleteHovered ? Color.red.opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Delete")
        .background(
            HoverTrackingView { hovering in isDeleteHovered = hovering }
        )
    }

    // MARK: - 分隔线

    private var toolbarSeparator: some View {
        Rectangle()
            .fill(Color(white: 0.88))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 3)
    }
}

// MARK: - 边框风格 Popover

struct ShapeStrokeStylePopover: View {
    let selected: ShapeStrokeStyle
    let onSelect: (ShapeStrokeStyle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            styleRow(.solid,  label: "Solid",  dash: [])
            styleRow(.dashed, label: "Dashed", dash: [6, 3])
            styleRow(.dotted, label: "Dotted", dash: [2, 3])
        }
        .padding(6)
        .frame(minWidth: 160)
    }

    private func styleRow(_ style: ShapeStrokeStyle, label: String, dash: [CGFloat]) -> some View {
        Button {
            onSelect(style)
        } label: {
            HStack(spacing: 10) {
                Canvas { ctx, size in
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height/2))
                    path.addLine(to: CGPoint(x: size.width, y: size.height/2))
                    let ss = StrokeStyle(lineWidth: 2, dash: dash)
                    ctx.stroke(path, with: .color(.primary), style: ss)
                }
                .frame(width: 36, height: 16)

                Text(label)
                    .font(.system(size: 13))

                Spacer()

                if selected == style {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 填充风格 Popover

struct ShapeFillStylePopover: View {
    let selected: ShapeFillStyle
    let onSelect: (ShapeFillStyle) -> Void

    private typealias StyleOption = (style: ShapeFillStyle, label: String, icon: String)

    private static let styles: [StyleOption] = [
        (style: .solid,        label: "Solid",         icon: "square.fill"),
        (style: .none,         label: "No Fill",       icon: "square"),
        (style: .hatched,      label: "Hatched",       icon: "square.lefthalf.filled"),
        (style: .crossHatched, label: "Cross Hatched", icon: "square.grid.2x2"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.styles, id: \.style) { option in
                Button {
                    onSelect(option.style)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: option.icon)
                            .font(.system(size: 14))
                            .frame(width: 20)

                        Text(option.label)
                            .font(.system(size: 13))

                        Spacer()

                        if selected == option.style {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(minWidth: 160)
    }
}
