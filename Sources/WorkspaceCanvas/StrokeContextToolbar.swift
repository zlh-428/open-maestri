import SwiftUI
import AppKit

struct StrokeContextToolbar: View {
    let nodeId: UUID
    let content: StrokeContent
    let onContentChange: (StrokeContent) -> Void
    let onDelete: () -> Void

    @State private var showThemeColorPicker = false
    @State private var showStrokeStylePicker = false
    @State private var isDeleteHovered = false

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

    private var themeColorButton: some View {
        Button { showThemeColorPicker = true } label: {
            ZStack {
                Circle()
                    .strokeBorder(themeColor, lineWidth: 3)
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(themeColor.opacity(0.3))
                    .frame(width: 14, height: 14)
            }
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Theme Color")
        .popover(isPresented: $showThemeColorPicker, arrowEdge: .bottom) {
            NoteColorPickerPopover(selectedColor: content.strokeColor) { color in
                var updated = content
                updated.strokeColor = color
                onContentChange(updated)
                showThemeColorPicker = false
            }
        }
    }

    private var strokeWidthStepper: some View {
        HStack(spacing: 2) {
            Button {
                var updated = content
                updated.strokeWidth = max(1, content.strokeWidth - 1)
                onContentChange(updated)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 30, height: 30)
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
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var strokeStyleButton: some View {
        Button { showStrokeStylePicker = true } label: {
            strokeStylePreview(content.strokeStyle)
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

    @ViewBuilder
    private func strokeStylePreview(_ style: ShapeStrokeStyle) -> some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: CGPoint(x: 4, y: size.height/2))
            path.addLine(to: CGPoint(x: size.width - 4, y: size.height/2))
            let ss: StrokeStyle
            switch style {
            case .solid:  ss = StrokeStyle(lineWidth: 2)
            case .dashed: ss = StrokeStyle(lineWidth: 2, dash: [6, 3])
            case .dotted: ss = StrokeStyle(lineWidth: 2, dash: [2, 3])
            }
            ctx.stroke(path, with: .color(.primary), style: ss)
        }
    }

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
        .background(HoverTrackingView { hovering in isDeleteHovered = hovering })
    }

    private var toolbarSeparator: some View {
        Rectangle()
            .fill(Color(white: 0.88))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 3)
    }
}
