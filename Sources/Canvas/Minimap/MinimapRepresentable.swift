import SwiftUI
import AppKit
import CoreGraphics

/// 将 MinimapView (NSView) 包装为 SwiftUI 视图
struct MinimapRepresentable: NSViewRepresentable {
    var nodeFrames: [CGRect]
    var canvasOrigin: CGPoint
    var zoom: CGFloat
    var onJumpTo: ((CGPoint) -> Void)?

    func makeNSView(context: Context) -> MinimapView {
        let view = MinimapView()
        view.onJumpTo = onJumpTo
        return view
    }

    func updateNSView(_ nsView: MinimapView, context: Context) {
        // 根据容器视图尺寸和 zoom 估算当前视口大小
        let viewportWidth: CGFloat = 800 / zoom
        let viewportHeight: CGFloat = 500 / zoom
        let viewportRect = CGRect(
            x: canvasOrigin.x,
            y: canvasOrigin.y,
            width: viewportWidth,
            height: viewportHeight
        )
        nsView.update(nodes: nodeFrames, viewport: viewportRect)
        nsView.onJumpTo = onJumpTo
    }
}
