import AppKit
import WebKit

// MARK: - Portal UIDelegate（处理 _blank 新窗口）

final class PortalUIDelegate: NSObject, WKUIDelegate {
    let portalId: UUID

    init(portalId: UUID) {
        self.portalId = portalId
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // target="_blank" 或 window.open()：在画布上新建 Portal 节点
        guard let url = navigationAction.request.url else { return nil }
        let urlString = url.absoluteString
        NotificationCenter.default.post(
            name: .portalOpenedNewWindow,
            object: nil,
            userInfo: ["url": urlString, "openerPortalId": portalId]
        )
        return nil
    }
}

// MARK: - Portal NavigationDelegate（处理自签名证书和重定向）

final class PortalNavigationDelegate: NSObject, WKNavigationDelegate {
    let portalId: UUID

    init(portalId: UUID) {
        self.portalId = portalId
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // 允许自签名证书（开发环境常见）
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in PortalWebViewStore.shared.navigationDidFinish(for: portalId) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in PortalWebViewStore.shared.navigationDidFail(for: portalId, error: error) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in PortalWebViewStore.shared.navigationDidFail(for: portalId, error: error) }
    }
}

/// Portal WKWebView 包装（直接 NSView，用于嵌入画布节点）
final class PortalWebView: NSView {
    private(set) var webView: WKWebView?

    func configure(portalId: UUID, url: String? = nil) {
        let wv = PortalWebViewStore.shared.createWebView(for: portalId, initialURL: url)
        webView = wv
        wv.frame = bounds
        wv.autoresizingMask = [.width, .height]
        addSubview(wv)
    }

    override func layout() {
        super.layout()
        webView?.frame = bounds
    }
}
