import SwiftUI

struct PortalNodeSwiftUIView: View {
    let nodeId: UUID
    let content: PortalContent
    let isSelected: Bool
    let isLocked: Bool
    let zoom: CGFloat
    var onActivated: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onDuplicate: ((UUID) -> Void)?
    var onLockToggle: ((UUID, Bool) -> Void)?

    var body: some View {
        NodeShellView(
            nodeId: nodeId,
            title: content.name,
            isSelected: isSelected,
            isLocked: isLocked,
            zoom: zoom,
            headerIcon: "globe",
            headerColor: .blue,
            onClose: { onClose?(nodeId) },
            onRename: { onRename?(nodeId, $0) },
            onDuplicate: { onDuplicate?(nodeId) },
            onLockToggle: { onLockToggle?(nodeId, $0) }
        ) {
            PortalWebViewRepresentable(nodeId: nodeId, content: content)
        }
    }
}

struct PortalWebViewRepresentable: NSViewRepresentable {
    let nodeId: UUID
    let content: PortalContent

    func makeNSView(context: Context) -> NSView {
        // 通过 PortalWebViewStore 获取或创建该 Portal 的 WKWebView
        if let webView = PortalWebViewStore.shared.webView(for: nodeId) {
            return webView
        }
        let webView = PortalWebViewStore.shared.createWebView(for: nodeId)
        if let url = URL(string: content.currentURL) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
