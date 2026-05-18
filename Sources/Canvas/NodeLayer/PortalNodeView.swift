import AppKit
import SwiftUI
import WebKit

// MARK: - Portal URL Chrome 控制栏（SwiftUI）

/// Portal 顶部 URL 控制栏（后退、刷新、URL 输入、加载指示、Chrome 隐藏切换）
struct PortalChromeBar: View {
    @Binding var urlText: String
    @Binding var isLoading: Bool
    let onNavigate: (String) -> Void
    let onBack: () -> Void
    let onRefresh: () -> Void
    let onToggleChrome: () -> Void

    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            // 后退按钮
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("后退")

            // 刷新 / 停止按钮
            Button(action: onRefresh) {
                Image(systemName: isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(isLoading ? "停止" : "刷新")

            // URL 输入框
            TextField("输入网址…", text: $urlText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .focused($isURLFieldFocused)
                .onSubmit { onNavigate(urlText) }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(NSColor.textBackgroundColor).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isURLFieldFocused ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 0.5)
                )

            // 加载指示
            if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }

            // Chrome 隐藏切换
            Button(action: onToggleChrome) {
                Image(systemName: "sidebar.squares.leading")
                    .font(.system(size: 11))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("隐藏/显示控制栏")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.95))
    }
}

// MARK: - Portal 节点视图

/// Portal 节点视图（包含 WKWebView + 顶部 URL 控制栏）
final class PortalNodeView: BaseNodeView {
    /// URL 控制栏高度
    static let chromeBarHeight: CGFloat = 32

    /// 对应的 Portal ID（由 CanvasNodeRenderer 赋值）
    var portalId: UUID?

    /// Chrome 是否隐藏（由右键菜单控制，或控制栏内按钮触发）
    private var isChromeHidden: Bool = false {
        didSet { updateChromeLayout() }
    }

    /// Chrome 栏 NSHostingView
    private var chromeBarHost: NSHostingView<AnyView>?
    /// URL 状态（通过 ObservableObject 桥接到 SwiftUI）
    private let chromeState = PortalChromeState()

    override func setup() {
        super.setup()
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupChromeBar()
    }

    private func setupChromeBar() {
        let bar = PortalChromeBar(
            urlText: Binding(
                get: { [weak self] in self?.chromeState.urlText ?? "" },
                set: { [weak self] v in self?.chromeState.urlText = v }
            ),
            isLoading: Binding(
                get: { [weak self] in self?.chromeState.isLoading ?? false },
                set: { [weak self] v in self?.chromeState.isLoading = v }
            ),
            onNavigate: { [weak self] url in self?.navigateTo(url) },
            onBack: { [weak self] in self?.webViewGoBack() },
            onRefresh: { [weak self] in self?.webViewRefresh() },
            onToggleChrome: { [weak self] in self?.toggleChrome() }
        )
        let host = NSHostingView(rootView: AnyView(bar))
        host.wantsLayer = true
        host.layer?.zPosition = 10
        addSubview(host)
        chromeBarHost = host
    }

    override func layout() {
        super.layout()
        updateChromeLayout()
    }

    private func updateChromeLayout() {
        let barH = Self.chromeBarHeight
        if isChromeHidden {
            chromeBarHost?.isHidden = true
            // webView 占满 contentView
            contentView.subviews.first?.frame = contentView.bounds
        } else {
            chromeBarHost?.isHidden = false
            let totalH = bounds.height
            let headerH: CGFloat = 28
            let chromeY = totalH - headerH - barH
            chromeBarHost?.frame = CGRect(x: 0, y: chromeY, width: bounds.width, height: barH)
            // 调整 contentView 上方让出 chrome bar 空间
            // contentView 已由 BaseNodeView 布局，这里调整嵌入的 WebView
            let webViewH = contentView.bounds.height - barH
            if webViewH > 0 {
                contentView.subviews.first?.frame = CGRect(
                    x: 0, y: 0, width: contentView.bounds.width, height: webViewH
                )
            }
        }
    }

    // MARK: - 导航控制

    private func navigateTo(_ urlString: String) {
        var finalURL = urlString
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            finalURL = "https://\(urlString)"
        }
        guard let id = portalId, let url = URL(string: finalURL) else { return }
        PortalWebViewStore.shared.webView(for: id)?.load(URLRequest(url: url))
    }

    private func webViewGoBack() {
        guard let id = portalId else { return }
        PortalWebViewStore.shared.webView(for: id)?.goBack()
    }

    private func webViewRefresh() {
        guard let id = portalId else { return }
        let wv = PortalWebViewStore.shared.webView(for: id)
        if wv?.isLoading == true {
            wv?.stopLoading()
        } else {
            wv?.reload()
        }
    }

    private func toggleChrome() {
        isChromeHidden = !isChromeHidden
    }

    /// 由 CanvasNodeRenderer 在嵌入 WebView 后调用，绑定导航事件以更新 URL/loading 状态
    func bindWebViewObservation(webView: WKWebView) {
        // KVO 监听 URL 变化
        observationTokens.append(
            webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.chromeState.urlText = wv.url?.absoluteString ?? ""
                }
            }
        )
        // KVO 监听加载状态
        observationTokens.append(
            webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.chromeState.isLoading = wv.isLoading
                }
            }
        )
    }

    private var observationTokens: [NSKeyValueObservation] = []

    // MARK: - 右键菜单

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "复制节点", action: #selector(duplicatePortal), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重命名", action: #selector(renamePortal), keyEquivalent: ""))
        menu.addItem(.separator())
        let chromeLabel = isChromeHidden ? "显示控制栏" : "隐藏控制栏"
        menu.addItem(NSMenuItem(title: chromeLabel, action: #selector(toggleChromeMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        let lockItem = NSMenuItem(title: isLocked ? "解锁" : "锁定",
                                  action: #selector(toggleLock), keyEquivalent: "")
        menu.addItem(lockItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "创建连接", action: #selector(startConnect), keyEquivalent: ""))
        menu.addItem(.separator())
        let closeItem = NSMenuItem(title: "删除", action: #selector(closePortal), keyEquivalent: "")
        let closeAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]
        closeItem.attributedTitle = NSAttributedString(string: "删除", attributes: closeAttrs)
        menu.addItem(closeItem)
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func duplicatePortal() { onDuplicate?() }
    @objc private func renamePortal() { startInlineRename() }
    @objc private func toggleChromeMenu() { toggleChrome() }
    @objc private func startConnect() { onConnect?() }
    @objc private func toggleLock() {
        isLocked = !isLocked
        onLockToggle?(isLocked)
    }
    @objc private func closePortal() { onClose?() }
}

// MARK: - Chrome 状态桥接

/// 用于从 AppKit 更新 SwiftUI 控制栏状态
@Observable
final class PortalChromeState {
    var urlText: String = ""
    var isLoading: Bool = false
}
