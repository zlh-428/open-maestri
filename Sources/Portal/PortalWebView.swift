import AppKit
import WebKit

// MARK: - Portal NavigationDelegate（处理自签名证书和重定向）

final class PortalNavigationDelegate: NSObject, WKNavigationDelegate {
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
