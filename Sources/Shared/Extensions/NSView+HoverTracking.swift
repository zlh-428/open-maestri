import AppKit
import SwiftUI

// MARK: - AppKit 级别 Hover 追踪（解决 NSViewRepresentable 上方 SwiftUI hover 失效问题）

/// 使用 NSTrackingArea 在 AppKit 层面检测 hover，绕过 SwiftUI .onHover 在 NSView 上方失效的问题
struct HoverTrackingView: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTrackingNSView {
        let view = HoverTrackingNSView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: HoverTrackingNSView, context: Context) {
        nsView.onHover = onHover
    }
}

class HoverTrackingNSView: NSView {
    var onHover: ((Bool) -> Void)?
    private var trackingRef: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}
