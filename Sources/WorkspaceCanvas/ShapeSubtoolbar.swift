import SwiftUI
import AppKit

struct ShapeSubtoolbar: View {
    @AppStorage("lastSelectedDrawingSubtool") var selectedSubtool: String = "rect"
    let onSubtoolChange: (String) -> Void

    @State private var showColorPicker = false
    @State private var showStrokeStylePicker = false
    @State private var showFillStylePicker = false

    @AppStorage("drawingDefaultColor") private var defaultColor: String = "#3B82F6"
    @AppStorage("drawingDefaultStrokeWidth") private var defaultStrokeWidth: Double = 2.0
    @AppStorage("drawingDefaultStrokeStyle") private var defaultStrokeStyleRaw: String = "solid"
    @AppStorage("drawingDefaultFillStyle") private var defaultFillStyleRaw: String = "solid"

    private var defaultStrokeStyle: ShapeStrokeStyle {
        ShapeStrokeStyle(rawValue: defaultStrokeStyleRaw) ?? .solid
    }
    private var defaultFillStyle: ShapeFillStyle {
        ShapeFillStyle(rawValue: defaultFillStyleRaw) ?? .solid
    }
    private var isClosedShape: Bool {
        ["rect", "ellipse", "diamond"].contains(selectedSubtool)
    }

    private static let subtools: [(id: String, icon: String, help: String)] = [
        ("freehand_pen",         "pencil",              "钢笔"),
        ("stroke_arrow",         "arrow.up.right",      "箭头"),
        ("freehand_highlighter", "highlighter",         "荧光笔"),
        ("stroke_line",          "minus",               "线条"),
        ("rect",                 "rectangle",           "矩形"),
        ("ellipse",              "circle",              "圆形"),
        ("diamond",              "diamond",             "菱形"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.subtools, id: \.id) { tool in
                subtoolButton(id: tool.id, icon: tool.icon, help: tool.help)
            }
            toolbarSeparator
            colorButton
            toolbarSeparator
            strokeWidthStepper
            toolbarSeparator
            strokeStyleButton
            if isClosedShape {
                toolbarSeparator
                fillStyleButton
            }
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

    private func subtoolButton(id: String, icon: String, help: String) -> some View {
        Button {
            selectedSubtool = id
            onSubtoolChange(id)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(selectedSubtool == id ? Color.accentColor : Color(white: 0.2))
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selectedSubtool == id ? Color.accentColor.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var colorButton: some View {
        Button { showColorPicker = true } label: {
            ZStack {
                Circle()
                    .strokeBorder(NoteColorPickerPopover.colorFromString(defaultColor), lineWidth: 3)
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(NoteColorPickerPopover.colorFromString(defaultColor).opacity(0.3))
                    .frame(width: 14, height: 14)
            }
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("主题颜色")
        .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
            NoteColorPickerPopover(selectedColor: defaultColor) { color in
                defaultColor = color
                showColorPicker = false
            }
        }
    }

    private var strokeWidthStepper: some View {
        HStack(spacing: 2) {
            Button {
                defaultStrokeWidth = max(1, defaultStrokeWidth - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 26)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            Text("\(Int(defaultStrokeWidth))pt")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(minWidth: 30, alignment: .center)

            Button {
                defaultStrokeWidth = min(20, defaultStrokeWidth + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 26)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }

    private var strokeStyleButton: some View {
        Button { showStrokeStylePicker = true } label: {
            strokeStylePreview(defaultStrokeStyle)
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("线条风格")
        .popover(isPresented: $showStrokeStylePicker, arrowEdge: .bottom) {
            ShapeStrokeStylePopover(selected: defaultStrokeStyle) { style in
                defaultStrokeStyleRaw = style.rawValue
                showStrokeStylePicker = false
            }
        }
    }

    private var fillStyleButton: some View {
        Button { showFillStylePicker = true } label: {
            fillStyleIcon(defaultFillStyle)
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.3))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("填充风格")
        .popover(isPresented: $showFillStylePicker, arrowEdge: .bottom) {
            ShapeFillStylePopover(selected: defaultFillStyle) { style in
                defaultFillStyleRaw = style.rawValue
                showFillStylePicker = false
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

    @ViewBuilder
    private func fillStyleIcon(_ style: ShapeFillStyle) -> some View {
        switch style {
        case .solid:        Image(systemName: "square.fill")
        case .none:         Image(systemName: "square")
        case .hatched:      Image(systemName: "square.lefthalf.filled")
        case .crossHatched: Image(systemName: "square.grid.2x2")
        }
    }

    private var toolbarSeparator: some View {
        Rectangle()
            .fill(Color(white: 0.88))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 3)
    }
}
