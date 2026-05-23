import Foundation
import WebKit
import OSLog

/// Portal WKWebView 实例管理器
/// 每个 Portal 节点持有独立 WKWebViewConfiguration（独立 Cookie/Storage）
@MainActor
final class PortalWebViewStore {
    static let shared = PortalWebViewStore()
    private let logger = Logger.make(category: "PortalWebViewStore")
    private var webViews: [UUID: WKWebView] = [:]
    private var navigationDelegates: [UUID: PortalNavigationDelegate] = [:]
    private var uiDelegates: [UUID: PortalUIDelegate] = [:]
    private var loadingContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    /// Portal URL 输入框引用（用于 AppKit 层聚焦）
    private var urlTextFields: [UUID: NSTextField] = [:]
    private init() {}

    // MARK: - URL TextField 管理

    func registerURLTextField(_ textField: NSTextField, for portalId: UUID) {
        urlTextFields[portalId] = textField
    }

    func unregisterURLTextField(for portalId: UUID) {
        urlTextFields.removeValue(forKey: portalId)
    }

    /// 通过 NSTextField 引用注销（dismantleNSView 场景下 nodeId 不易获取）
    func unregisterURLTextField(matching textField: NSTextField) {
        if let key = urlTextFields.first(where: { $0.value === textField })?.key {
            urlTextFields.removeValue(forKey: key)
        }
    }

    func urlTextField(for portalId: UUID) -> NSTextField? {
        urlTextFields[portalId]
    }

    // MARK: - WebView 生命周期

    /// sharedDataStores: portal-portal 连接组 → 共享 WKWebsiteDataStore
    private var sharedDataStores: [UUID: WKWebsiteDataStore] = [:]  // groupId → store
    private var portalGroups: [UUID: UUID] = [:]                     // portalId → groupId

    func createWebView(for portalId: UUID, initialURL: String? = nil, sharedGroupId: UUID? = nil) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 独立 Portal 使用非持久化存储（storageScope: isolated）
        // Portal-Portal 连接时共享同一 WKWebsiteDataStore
        if let groupId = sharedGroupId {
            if let existing = sharedDataStores[groupId] {
                config.websiteDataStore = existing
            } else {
                let store = WKWebsiteDataStore.nonPersistent()
                sharedDataStores[groupId] = store
                config.websiteDataStore = store
            }
            portalGroups[portalId] = groupId
        } else {
            // 每个 Portal 默认独立存储（非持久化，避免 Cookie 污染）
            config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        // 设置 navigationDelegate 处理证书挑战（允许自签名 HTTPS）
        let delegate = PortalNavigationDelegate(portalId: portalId)
        webView.navigationDelegate = delegate
        // 设置 uiDelegate 处理 target="_blank" / window.open() 新窗口请求
        let uiDelegate = PortalUIDelegate(portalId: portalId)
        webView.uiDelegate = uiDelegate
        // 保留 delegate 引用避免被 ARC 释放
        navigationDelegates[portalId] = delegate
        uiDelegates[portalId] = uiDelegate
        webViews[portalId] = webView

        if let urlStr = initialURL, let url = URL(string: urlStr) {
            webView.load(URLRequest(url: url))
        }
        logger.debug("WebView created for portal \(portalId.uuidString.prefix(8))")
        return webView
    }

    @discardableResult
    func createWebView(for portalId: UUID, initialURL: String? = nil) -> WKWebView {
        createWebView(for: portalId, initialURL: initialURL, sharedGroupId: nil)
    }

    func removeWebView(for portalId: UUID) {
        webViews[portalId]?.stopLoading()
        webViews.removeValue(forKey: portalId)
        navigationDelegates.removeValue(forKey: portalId)
        uiDelegates.removeValue(forKey: portalId)
        loadingContinuations.removeValue(forKey: portalId)?.resume()
        // 清理共享组（如果是最后一个成员）
        if let groupId = portalGroups.removeValue(forKey: portalId) {
            let remaining = portalGroups.values.filter { $0 == groupId }
            if remaining.isEmpty { sharedDataStores.removeValue(forKey: groupId) }
        }
    }

    func webView(for portalId: UUID) -> WKWebView? {
        webViews[portalId]
    }

    // MARK: - Portal↔Portal session 共享（FR31）

    /// 建立 Portal-Portal 连接时共享 session
    /// 注意：WKWebView 创建后无法更改 dataStore，因此需要重建 WebView
    func shareSession(portalIdA: UUID, portalIdB: UUID) {
        let groupId = portalGroups[portalIdA] ?? UUID()
        let urlA = webViews[portalIdA]?.url?.absoluteString
        let urlB = webViews[portalIdB]?.url?.absoluteString

        // 停止旧 WebView
        webViews[portalIdA]?.stopLoading()
        webViews[portalIdB]?.stopLoading()
        webViews.removeValue(forKey: portalIdA)
        webViews.removeValue(forKey: portalIdB)

        // 创建共享 session 的新 WebView
        let newA = createWebView(for: portalIdA, initialURL: urlA, sharedGroupId: groupId)
        let newB = createWebView(for: portalIdB, initialURL: urlB, sharedGroupId: groupId)

        // 通知 CanvasNodeRenderer 更新 Portal 视图中嵌入的 WebView
        NotificationCenter.default.post(
            name: .portalWebViewReplaced,
            object: nil,
            userInfo: ["portalIdA": portalIdA, "webViewA": newA, "portalIdB": portalIdB, "webViewB": newB]
        )
        logger.info("Session shared: portal \(portalIdA.uuidString.prefix(8)) ↔ \(portalIdB.uuidString.prefix(8)) (group: \(groupId.uuidString.prefix(8)))")
    }

    // MARK: - Navigation 回调（由 PortalNavigationDelegate 调用）

    func navigationDidFinish(for portalId: UUID) {
        loadingContinuations.removeValue(forKey: portalId)?.resume()
    }

    func navigationDidFail(for portalId: UUID, error: Error) {
        loadingContinuations.removeValue(forKey: portalId)?.resume(throwing: error)
    }

    // MARK: - Portal 自动化命令（omaestri portal）

    func goBack(portalId: UUID) async throws {
        guard let wv = webViews[portalId] else {
            throw MaestriError.portalCommandFailed("Portal not found: \(portalId)")
        }
        await MainActor.run { wv.goBack() }
    }

    func goForward(portalId: UUID) async throws {
        guard let wv = webViews[portalId] else {
            throw MaestriError.portalCommandFailed("Portal not found: \(portalId)")
        }
        await MainActor.run { wv.goForward() }
    }

    func reload(portalId: UUID) async throws {
        guard let wv = webViews[portalId] else {
            throw MaestriError.portalCommandFailed("Portal not found: \(portalId)")
        }
        await MainActor.run { wv.reload() }
    }

    func navigate(portalId: UUID, to urlString: String) async throws {
        guard let wv = webViews[portalId],
              let url = URL(string: urlString) else {
            throw MaestriError.portalCommandFailed("Invalid URL or portal not found: \(urlString)")
        }
        // 取消之前未完成的 navigation（如有）
        loadingContinuations.removeValue(forKey: portalId)?.resume()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadingContinuations[portalId] = continuation
            wv.load(URLRequest(url: url))
            // 15 秒超时保护：超时后不报错，直接继续
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                self?.loadingContinuations.removeValue(forKey: portalId)?.resume()
            }
        }
    }

    func screenshot(portalId: UUID) async throws -> String {
        guard let wv = webViews[portalId] else {
            throw MaestriError.portalCommandFailed("Portal not found: \(portalId)")
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let config = WKSnapshotConfiguration()
                wv.takeSnapshot(with: config) { image, error in
                    guard let image, error == nil else {
                        continuation.resume(returning: "error: snapshot failed")
                        return
                    }
                    let data = image.tiffRepresentation ?? Data()
                    continuation.resume(returning: data.base64EncodedString())
                }
            }
        }
    }

    func evaluate(portalId: UUID, javascript: String) async throws -> String {
        guard let wv = webViews[portalId] else {
            throw MaestriError.portalCommandFailed("Portal not found: \(portalId)")
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                wv.evaluateJavaScript(javascript) { result, error in
                    if let error {
                        continuation.resume(throwing: MaestriError.portalCommandFailed(error.localizedDescription))
                    } else {
                        continuation.resume(returning: "\(result ?? "")")
                    }
                }
            }
        }
    }
}
