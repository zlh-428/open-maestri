import SwiftUI

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

    @State private var isEditing = false

    var body: some View {
        NodeShellView(
            nodeId: nodeId,
            title: "Text",
            isSelected: isSelected,
            isLocked: isLocked,
            zoom: zoom,
            headerIcon: "text.alignleft",
            headerColor: .purple,
            onClose: { onClose?(nodeId) },
            onRename: { onRename?(nodeId, $0) },
            onDuplicate: { onDuplicate?(nodeId) },
            onLockToggle: { onLockToggle?(nodeId, $0) }
        ) {
            Group {
                if isEditing {
                    TextEditor(text: .constant(content.text))
                        .font(.system(size: CGFloat(content.fontSize) / zoom))
                        .allowsHitTesting(true)
                } else {
                    Text(content.text)
                        .font(.system(size: CGFloat(content.fontSize) / zoom))
                        .foregroundStyle(Color(hex: content.color) ?? .primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(8 / zoom)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
