import SwiftUI
import AppKit

struct TextNodeSwiftUIView: View {
    let nodeId: UUID
    let content: TextContent
    let isSelected: Bool
    let isLocked: Bool
    let zoom: CGFloat
    var onActivated: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onDuplicate: ((UUID) -> Void)?
    var onLockToggle: ((UUID, Bool) -> Void)?

    @Environment(\.textNodeEditingId) private var editingId

    private var isEditing: Bool { editingId == nodeId }
    private var showPlaceholder: Bool { content.text.isEmpty && !isEditing }

    var body: some View {
        ZStack {
            if isSelected || isEditing {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
                    .foregroundStyle(Color.accentColor)
            }

            if isEditing {
                TextFieldRepresentable(nodeId: nodeId, content: content)
                    .padding(6)
            } else if showPlaceholder {
                Text("Text")
                    .font(resolvedFont)
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                Text(content.text)
                    .font(resolvedFont)
                    .foregroundStyle(Color(hex: content.color) ?? .primary)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .lineLimit(1)
            }
        }
        .allowsHitTesting(false)
    }

    private var resolvedFont: Font {
        let size = content.fontSize
        let weight: Font.Weight = {
            switch content.fontWeight {
            case "bold":   return .bold
            case "medium": return .medium
            default:       return .regular
            }
        }()
        switch content.fontFamily {
        case "serif": return .system(size: size, weight: weight, design: .serif)
        case "mono":  return .system(size: size, weight: weight, design: .monospaced)
        default:      return .system(size: size, weight: weight, design: .default)
        }
    }
}

// MARK: - NSTextField Representable

struct TextFieldRepresentable: NSViewRepresentable {
    let nodeId: UUID
    let content: TextContent

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.lineBreakMode = .byClipping
        tf.cell?.isScrollable = true
        tf.cell?.wraps = false
        tf.delegate = context.coordinator
        // 首次创建时请求聚焦，仅触发一次
        DispatchQueue.main.async {
            tf.window?.makeFirstResponder(tf)
        }
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        if tf.currentEditor() == nil {
            tf.stringValue = content.text
            applyStyle(to: tf)
        }
    }

    private func applyStyle(to tf: NSTextField) {
        let size = content.fontSize
        let weight: NSFont.Weight = {
            switch content.fontWeight {
            case "bold":   return .bold
            case "medium": return .medium
            default:       return .regular
            }
        }()
        let baseDescriptor: NSFontDescriptor
        switch content.fontFamily {
        case "serif":
            baseDescriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
                .withDesign(.serif) ?? NSFont.systemFont(ofSize: size).fontDescriptor
        case "mono":
            baseDescriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
                .withDesign(.monospaced) ?? NSFont.systemFont(ofSize: size).fontDescriptor
        default:
            baseDescriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
        }
        let weightedDescriptor = baseDescriptor.addingAttributes(
            [.traits: [NSFontDescriptor.TraitKey.weight: weight]]
        )
        let newFont = NSFont(descriptor: weightedDescriptor, size: size) ?? NSFont.systemFont(ofSize: size)
        if tf.font != newFont { tf.font = newFont }
        let newColor = NSColor(hex: content.color) ?? NSColor.labelColor
        if tf.textColor != newColor { tf.textColor = newColor }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(nodeId: nodeId)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let nodeId: UUID

        init(nodeId: UUID) {
            self.nodeId = nodeId
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            NotificationCenter.default.post(
                name: .textNodeDidChange,
                object: nil,
                userInfo: ["nodeId": nodeId, "text": tf.stringValue, "textField": tf]
            )
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            NotificationCenter.default.post(
                name: .textNodeDidEndEditing,
                object: nil,
                userInfo: ["nodeId": nodeId, "text": tf.stringValue]
            )
        }
    }
}

// MARK: - Environment Key

struct TextNodeEditingIdKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var textNodeEditingId: UUID? {
        get { self[TextNodeEditingIdKey.self] }
        set { self[TextNodeEditingIdKey.self] = newValue }
    }
}
