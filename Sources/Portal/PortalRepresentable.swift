import SwiftUI
import AppKit
import WebKit

/// PortalWebView 的 SwiftUI 包装
struct PortalRepresentable: NSViewRepresentable {
    let portalId: UUID
    let url: String

    func makeNSView(context: Context) -> PortalWebView {
        let view = PortalWebView()
        view.configure(portalId: portalId, url: url)
        return view
    }

    func updateNSView(_ nsView: PortalWebView, context: Context) {}
}
