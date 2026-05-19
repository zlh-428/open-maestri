import SwiftUI
import AppKit

struct DrawingNodeSwiftUIView: View {
    let nodeId: UUID
    let content: DrawingContent
    let isSelected: Bool
    let isLocked: Bool
    let zoom: CGFloat
    var onActivated: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onLockToggle: ((UUID, Bool) -> Void)?

    var body: some View {
        NodeShellView(
            nodeId: nodeId,
            title: "Drawing",
            isSelected: isSelected,
            isLocked: isLocked,
            zoom: zoom,
            headerIcon: "pencil",
            headerColor: .gray,
            onClose: { onClose?(nodeId) },
            onLockToggle: { onLockToggle?(nodeId, $0) }
        ) {
            Canvas { context, size in
                for stroke in content.strokes {
                    guard stroke.points.count > 1 else { continue }
                    var path = Path()
                    path.move(to: CGPoint(x: stroke.points[0][0] * zoom, y: stroke.points[0][1] * zoom))
                    for i in 1..<stroke.points.count {
                        path.addLine(to: CGPoint(x: stroke.points[i][0] * zoom, y: stroke.points[i][1] * zoom))
                    }
                    context.stroke(path, with: .color(Color(hex: stroke.color) ?? .black),
                                   lineWidth: stroke.width)
                }
            }
            .allowsHitTesting(false)
        }
    }
}
