import SwiftUI
import WebKit
import Combine

// MARK: - Portal 导航状态（KVO 桥接 WKWebView → SwiftUI）

// 使用 ObservableObject 而非 @Observable：此类作为视图私有状态由 @StateObject 管理，
// @StateObject 确保跨 body 重计算时对象实例不被重建，避免 makeNSView 被重复调用。
@MainActor
final class PortalNavState: ObservableObject {
    @Published var urlText: String = ""
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var isEditingURL: Bool = false
    /// WebView 是否已导航过至少一个页面（区分真正空状态）
    @Published var hasNavigated: Bool = false

    private var observations: [NSKeyValueObservation] = []

    func observe(_ webView: WKWebView) {
        observations.removeAll()
        urlText = webView.url?.absoluteString ?? ""
        if webView.url != nil { hasNavigated = true }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading

        observations = [
            webView.observe(\.url, options: .new) { [weak self] wv, _ in
                let newURL = wv.url?.absoluteString ?? ""
                let hasURL = wv.url != nil
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if hasURL && !self.hasNavigated { self.hasNavigated = true }
                    if !self.isEditingURL && self.urlText != newURL { self.urlText = newURL }
                }
            },
            webView.observe(\.canGoBack, options: .new) { [weak self] wv, _ in
                let val = wv.canGoBack
                Task { @MainActor [weak self] in
                    guard let self, self.canGoBack != val else { return }
                    self.canGoBack = val
                }
            },
            webView.observe(\.canGoForward, options: .new) { [weak self] wv, _ in
                let val = wv.canGoForward
                Task { @MainActor [weak self] in
                    guard let self, self.canGoForward != val else { return }
                    self.canGoForward = val
                }
            },
            webView.observe(\.isLoading, options: .new) { [weak self] wv, _ in
                let val = wv.isLoading
                Task { @MainActor [weak self] in
                    guard let self, self.isLoading != val else { return }
                    self.isLoading = val
                }
            },
        ]
    }

    func stopObserving() {
        observations.removeAll()
    }
}

// MARK: - Portal 导航工具栏（双胶囊样式）

struct PortalNavBarView: View {
    @ObservedObject var state: PortalNavState
    let nodeId: UUID
    let onGoBack: () -> Void
    let onGoForward: () -> Void
    let onRefresh: () -> Void
    let onNavigate: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            // 左侧胶囊：后退 / 前进 / 刷新
            HStack(spacing: 0) {
                Button(action: onGoBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(!state.canGoBack)
                .opacity(state.canGoBack ? 1 : 0.35)

                Button(action: onGoForward) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(!state.canGoForward)
                .opacity(state.canGoForward ? 1 : 0.35)

                Button(action: {
                    onRefresh()
                }) {
                    Image(systemName: state.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            )

            // 右侧胶囊：URL 输入框
            PortalURLField(state: state, nodeId: nodeId, onNavigate: onNavigate)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            VibrancyBackground(material: .sidebar, blendingMode: .behindWindow)
        }
    }
}

// MARK: - URL 输入框（SwiftUI 胶囊容器 + 内嵌 NSTextField）

struct PortalURLField: View {
    @ObservedObject var state: PortalNavState
    let nodeId: UUID
    let onNavigate: (String) -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 12, height: 12)

            PortalURLTextFieldRepresentable(
                state: state,
                nodeId: nodeId,
                onNavigate: onNavigate
            )
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(
            Capsule()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        )
    }
}

/// 内嵌 NSTextField（仅负责文本输入，不带容器样式）
struct PortalURLTextFieldRepresentable: NSViewRepresentable {
    @ObservedObject var state: PortalNavState
    let nodeId: UUID
    let onNavigate: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onNavigate: onNavigate)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 11)
        textField.placeholderString = "portal.url_placeholder".localized
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        textField.lineBreakMode = .byTruncatingTail
        textField.delegate = context.coordinator
        textField.stringValue = state.urlText
        context.coordinator.textField = textField

        // 注册到 Store 以便 AppKit 层聚焦
        Task { @MainActor in
            PortalWebViewStore.shared.registerURLTextField(textField, for: nodeId)
        }
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.onNavigate = onNavigate
        // 非编辑状态才同步文本；用标记屏蔽程序化写入触发的 controlTextDidChange → urlText 死循环
        if !state.isEditingURL && nsView.stringValue != state.urlText {
            context.coordinator.isProgrammaticUpdate = true
            nsView.stringValue = state.urlText
            context.coordinator.isProgrammaticUpdate = false
        }
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        // 注销 URL TextField 引用
        coordinator.unregisterFromStore()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var state: PortalNavState
        var onNavigate: (String) -> Void
        weak var textField: NSTextField?
        private var nodeId: UUID?
        /// 程序化写入 stringValue 期间置 true，避免触发 controlTextDidChange → urlText 循环
        var isProgrammaticUpdate: Bool = false

        init(state: PortalNavState, onNavigate: @escaping (String) -> Void) {
            self.state = state
            self.onNavigate = onNavigate
        }

        func setNodeId(_ id: UUID) { nodeId = id }

        func unregisterFromStore() {
            // dismantleNSView 中调用；遍历方式兜底
            guard let tf = textField else { return }
            Task { @MainActor in
                // 查找并注销
                PortalWebViewStore.shared.unregisterURLTextField(matching: tf)
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            Task { @MainActor in self.state.isEditingURL = true }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            Task { @MainActor in self.state.isEditingURL = false }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let text = textView.string
                Task { @MainActor in
                    self.state.isEditingURL = false
                    self.onNavigate(text)
                }
                // 失焦
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }

        func controlTextDidChange(_ obj: Notification) {
            guard !isProgrammaticUpdate,
                  let textField = obj.object as? NSTextField else { return }
            Task { @MainActor in self.state.urlText = textField.stringValue }
        }
    }
}

// MARK: - Portal 空状态视图

struct PortalEmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(Color(white: 0.7))

            Text("portal.empty_state")
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.97))
    }
}

// MARK: - Portal 节点视图

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

    @StateObject private var navState = PortalNavState()

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
            VStack(spacing: 0) {
                PortalNavBarView(
                    state: navState,
                    nodeId: nodeId,
                    onGoBack: {
                        PortalWebViewStore.shared.webView(for: nodeId)?.goBack()
                    },
                    onGoForward: {
                        PortalWebViewStore.shared.webView(for: nodeId)?.goForward()
                    },
                    onRefresh: {
                        let wv = PortalWebViewStore.shared.webView(for: nodeId)
                        if wv?.isLoading == true { wv?.stopLoading() } else { wv?.reload() }
                    },
                    onNavigate: { urlStr in
                        let trimmed = urlStr.trimmingCharacters(in: .whitespaces)
                        // 空输入或仅协议前缀：恢复当前页面 URL，不导航
                        if trimmed.isEmpty || trimmed == "https://" || trimmed == "http://" {
                            let currentURL = PortalWebViewStore.shared.webView(for: nodeId)?.url?.absoluteString ?? ""
                            navState.urlText = currentURL
                            return
                        }
                        let normalized = normalizedURL(trimmed)
                        guard let url = URL(string: normalized) else { return }
                        PortalWebViewStore.shared.webView(for: nodeId)?.load(URLRequest(url: url))
                    }
                )

                Divider().opacity(0.3)

                // WebView 和空状态始终共存（ZStack），避免条件切换导致 WebView 重建
                ZStack {
                    PortalWebViewRepresentable(nodeId: nodeId, initialURL: content.currentURL, navState: navState)
                        .equatable()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !navState.hasNavigated {
                        PortalEmptyStateView()
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func normalizedURL(_ raw: String) -> String {
        var str = raw.trimmingCharacters(in: .whitespaces)
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "https://" + str
        }
        return str
    }
}

// MARK: - WKWebView NSViewRepresentable

struct PortalWebViewRepresentable: NSViewRepresentable {
    let nodeId: UUID
    let initialURL: String
    let navState: PortalNavState

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let webView: WKWebView
        if let existing = PortalWebViewStore.shared.webView(for: nodeId) {
            webView = existing
        } else {
            webView = PortalWebViewStore.shared.createWebView(for: nodeId)
            // 仅在有有效 URL 时首次加载
            let url = initialURL.trimmingCharacters(in: .whitespaces)
            if !url.isEmpty && url != "https://" && url != "http://",
               let loadURL = URL(string: url) {
                webView.load(URLRequest(url: loadURL))
            }
        }
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)

        // observe 只在此处调用一次，避免 updateNSView 重复 observe 引发刷新循环
        navState.observe(webView)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // 仅修正布局：WebView 被移到旧容器时归位，不重新 observe（避免 KVO→navState→SwiftUI→updateNSView 循环）
        guard let webView = PortalWebViewStore.shared.webView(for: nodeId) else { return }
        if webView.superview !== nsView {
            webView.removeFromSuperview()
            webView.frame = nsView.bounds
            webView.autoresizingMask = [.width, .height]
            nsView.addSubview(webView)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        // WebView 由 PortalWebViewStore 管理生命周期，不在此销毁
        // 但需要从容器中移除以避免被释放
        for subview in nsView.subviews where subview is WKWebView {
            subview.removeFromSuperview()
        }
    }
}

extension PortalWebViewRepresentable: Equatable {
    static func == (lhs: PortalWebViewRepresentable, rhs: PortalWebViewRepresentable) -> Bool {
        // 只用 nodeId 区分身份；initialURL 仅在 makeNSView 首次加载时使用，
        // 后续 currentURL 持久化写回 content 时不应触发 WebView 重建
        lhs.nodeId == rhs.nodeId
    }
}
