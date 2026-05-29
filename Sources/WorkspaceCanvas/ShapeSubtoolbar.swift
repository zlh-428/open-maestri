import SwiftUI
import AppKit

struct ShapeSubtoolbar: View {
    @AppStorage("lastSelectedDrawingSubtool") var selectedSubtool: String = "rect"
    let onSubtoolChange: (String) -> Void

    @State private var showColorPicker = false
    @State private var showStrokeStylePicker = false
    @State private var showFillStylePicker = false

    @AppStorage("drawingDefaultColor") private var defaultColor: String = "blue"
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

    private static let subtools: [(id: String, icon: String, helpKey: String)] = [
        ("freehand_pen",         "pencil",              "draw.tool.pen"),
        ("stroke_arrow",         "arrow.up.right",      "draw.tool.arrow"),
        ("freehand_highlighter", "highlighter",         "draw.tool.highlighter"),
        ("stroke_line",          "line.diagonal",       "draw.tool.line"),
        ("rect",                 "rectangle",           "draw.tool.rect"),
        ("ellipse",              "circle",              "draw.tool.ellipse"),
        ("diamond",              "diamond",             "draw.tool.diamond"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.subtools, id: \.id) { tool in
                subtoolButton(id: tool.id, icon: tool.icon, help: tool.helpKey.localized)
            }
            toolbarSeparator
            colorButton
            toolbarSeparator
            strokeWidthStepper
            toolbarSeparator
            fillStyleButton
            toolbarSeparator
            strokeStyleButton
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
            Circle()
                .fill(NoteColorPickerPopover.colorFromString(defaultColor))
                .frame(width: 18, height: 18)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("draw.help.theme_color".localized)
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
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(white: 0.3))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("draw.help.stroke_style".localized)
        .popover(isPresented: $showStrokeStylePicker, arrowEdge: .bottom) {
            ShapeStrokeStylePopover(selected: defaultStrokeStyle) { style in
                defaultStrokeStyleRaw = style.rawValue
                showStrokeStylePicker = false
            }
        }
    }

    private var fillStyleButton: some View {
        Button { showFillStylePicker = true } label: {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(white: 0.3))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("draw.help.fill_style".localized)
        .popover(isPresented: $showFillStylePicker, arrowEdge: .bottom) {
            ShapeFillStylePopover(selected: defaultFillStyle) { style in
                defaultFillStyleRaw = style.rawValue
                showFillStylePicker = false
            }
        }
    }

    private var toolbarSeparator: some View {
        Rectangle()
            .fill(Color(white: 0.88))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 3)
    }
}
