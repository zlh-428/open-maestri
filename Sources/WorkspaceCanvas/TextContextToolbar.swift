import SwiftUI
import AppKit

struct TextContextToolbar: View {
    let nodeId: UUID
    let fontSize: CGFloat
    let fontWeight: String
    let fontFamily: String
    let currentColor: String

    let onFontSize: (CGFloat) -> Void
    let onFontWeight: (String) -> Void
    let onFontFamily: (String) -> Void
    let onColor: (String) -> Void
    let onDelete: () -> Void

    @State private var showColorPicker = false
    @State private var localFontSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 2) {
            fontSizeControls

            toolbarSeparator

            weightButton("R", weight: "regular")
            weightButton("M", weight: "medium")
            weightButton("B", weight: "bold")

            toolbarSeparator

            familyButton("Sans",  family: "sans")
            familyButton("Serif", family: "serif")
            familyButton("Mono",  family: "mono")
            systemFontButton

            toolbarSeparator

            colorButton

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
        .onAppear { localFontSize = fontSize }
        .onChange(of: fontSize) { newSize in localFontSize = newSize }
    }

    // MARK: - 字号控件

    private var fontSizeControls: some View {
        HStack(spacing: 0) {
            Button {
                let newSize = max(8, localFontSize - 1)
                localFontSize = newSize
                onFontSize(newSize)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("\(Int(localFontSize))")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(minWidth: 28, alignment: .center)

            Button {
                let newSize = min(96, localFontSize + 1)
                localFontSize = newSize
                onFontSize(newSize)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 字重按钮

    @ViewBuilder
    private func weightButton(_ label: String, weight: String) -> some View {
        let isActive = fontWeight == weight
        let fontWeight_: Font.Weight = weight == "bold" ? .bold : weight == "medium" ? .medium : .regular
        Button { onFontWeight(weight) } label: {
            Text(label)
                .font(.system(size: 13, weight: fontWeight_))
                .foregroundStyle(isActive ? Color.accentColor : Color(white: 0.3))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 字体族按钮

    @ViewBuilder
    private func familyButton(_ label: String, family: String) -> some View {
        let isActive = fontFamily == family
        let font: Font = family == "serif" ? .system(size: 12, design: .serif)
            : family == "mono" ? .system(size: 12, design: .monospaced)
            : .system(size: 12)
        Button { onFontFamily(family) } label: {
            Text(label)
                .font(font)
                .foregroundStyle(isActive ? Color.accentColor : Color(white: 0.3))
                .frame(width: 36, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 系统字体按钮 (Aa)

    private var systemFontButton: some View {
        Button { NSFontManager.shared.orderFrontFontPanel(nil) } label: {
            Text("Aa")
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.45))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Custom Font (preview only)")
        .opacity(0.6)
    }

    // MARK: - 颜色按钮

    private var colorButton: some View {
        Button { showColorPicker = true } label: {
            Circle()
                .fill(NoteColorPickerPopover.colorFromString(currentColor))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color(white: 0.7), lineWidth: 1))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Text Color")
        .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
            NoteColorPickerPopover(selectedColor: currentColor) { color in
                onColor(color)
                showColorPicker = false
            }
        }
    }

    // MARK: - 删除按钮

    private var deleteButton: some View {
        NoteToolbarButton(icon: "trash", tooltip: "Delete", isDestructive: true, action: onDelete)
    }

    // MARK: - 分隔线

    private var toolbarSeparator: some View {
        Rectangle()
            .fill(Color(white: 0.88))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 3)
    }
}
