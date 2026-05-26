import AppKit
import WebKit

extension CanvasViewportView {

    // MARK: - 终端鼠标坐标修正

    /// 修正转发给终端视图的鼠标事件坐标。
    ///
    /// 问题背景：节点通过 SwiftUI `.scaleEffect(zoom)` 缩放，这是 CALayer transform，
    /// 不影响 NSView 的 frame/bounds。因此 SwiftTerm 内部的
    /// `convert(event.locationInWindow, from: nil)` 基于 NSView 层级计算坐标时
    /// 不考虑 layer transform，导致映射到错误的终端行列位置。
    ///
    /// 修正方案：
    /// 1. 从画布屏幕坐标计算鼠标在终端内容区的相对位置（已缩放）
    /// 2. 除以 zoom 得到终端视图的本地坐标（未缩放）
    /// 3. 用 terminalView 自身的 convert(to: nil) 反向合成正确的窗口坐标
    ///    使 SwiftTerm 的 convert(from: nil) 能正确还原到本地坐标
    func correctedWindowLocation(for event: NSEvent, nodeId: UUID, terminalView: NSView) -> CGPoint {
        let loc = convert(event.locationInWindow, from: nil)

        guard let node = currentNodes.first(where: { $0.id == nodeId }) else {
            return event.locationInWindow
        }

        let screenFrame = canvasRectToScreen(node.frame)
        let scaledHeaderHeight = CanvasNodeConstants.headerHeight * zoom

        // 终端节点有 footer，需要减去；加上 divider（约 1pt 缩放后）
        let scaledDividerHeight: CGFloat = 1.0 * zoom

        // 鼠标在节点内容区中的相对位置（屏幕坐标，已乘以 zoom）
        let relX = loc.x - screenFrame.minX
        let relY = loc.y - screenFrame.minY - scaledHeaderHeight - scaledDividerHeight

        // 转为终端视图本地坐标（未缩放）
        // SwiftTerm TerminalView 是非 flipped 的（y 从底部向上），需要翻转 y 轴
        let tvHeight = terminalView.bounds.height
        let localX = relX / zoom
        let localY = tvHeight - (relY / zoom)

        // 用 terminalView 自身的坐标系统转回窗口坐标
        // 这样 SwiftTerm 调用 convert(locationInWindow, from: nil) 时得到 (localX, localY)
        return terminalView.convert(CGPoint(x: localX, y: localY), to: nil)
    }

    /// Portal WKWebView 坐标修正
    /// WKWebView 是 flipped 坐标系（y 从上到下），且 Portal 节点有 header + navBar + divider 偏移
    func correctedWindowLocationForWebView(for event: NSEvent, nodeId: UUID, webView: NSView) -> CGPoint {
        let loc = convert(event.locationInWindow, from: nil)

        guard let node = currentNodes.first(where: { $0.id == nodeId }) else {
            return event.locationInWindow
        }

        let screenFrame = canvasRectToScreen(node.frame)
        // Portal 内容区偏移：header(32) + navBar padding(6) + navBar height(28) + padding(6) + divider(1) = 73
        let contentTopOffset: CGFloat = 73.0
        let scaledContentTop = contentTopOffset * zoom

        // 鼠标在 WebView 内容区中的相对位置（屏幕坐标）
        let relX = loc.x - screenFrame.minX
        let relY = loc.y - screenFrame.minY - scaledContentTop

        // 转为 WebView 本地坐标（未缩放）
        // WKWebView 是 flipped（y 从上到下），与屏幕坐标系一致（AppKit 的 y 向下）
        let localX = relX / zoom
        let localY = relY / zoom

        // 用 webView 自身坐标系统转回窗口坐标
        return webView.convert(CGPoint(x: localX, y: localY), to: nil)
    }

    /// NSTextView 坐标修正（Shape 节点）
    /// Shape 节点无 header/footer，NSTextView 覆盖整个节点 frame，只需减去 frame 原点
    func correctedWindowLocationForShapeTextView(for event: NSEvent, nodeId: UUID, textView: NSView) -> CGPoint {
        let loc = convert(event.locationInWindow, from: nil)

        guard let node = currentNodes.first(where: { $0.id == nodeId }) else {
            return event.locationInWindow
        }

        let screenFrame = canvasRectToScreen(node.frame)

        let relX = loc.x - screenFrame.minX
        let relY = loc.y - screenFrame.minY

        let localX = relX / zoom
        let localY = relY / zoom

        return textView.convert(CGPoint(x: localX, y: localY), to: nil)
    }

    /// NSTextView 坐标修正（Note 节点）
    /// NSTextView 默认 isFlipped=true（y 从上到下），与屏幕坐标系一致，不需要翻转 y 轴
    func correctedWindowLocationForTextView(for event: NSEvent, nodeId: UUID, textView: NSView) -> CGPoint {
        let loc = convert(event.locationInWindow, from: nil)

        guard let node = currentNodes.first(where: { $0.id == nodeId }) else {
            return event.locationInWindow
        }

        let screenFrame = canvasRectToScreen(node.frame)
        let scaledHeaderHeight = CanvasNodeConstants.headerHeight * zoom
        let scaledDividerHeight: CGFloat = 1.0 * zoom

        // 鼠标在 NSTextView 内容区中的相对位置（屏幕坐标）
        let relX = loc.x - screenFrame.minX
        let relY = loc.y - screenFrame.minY - scaledHeaderHeight - scaledDividerHeight

        // NSTextView 是 flipped（y 从上到下），与屏幕坐标方向一致，直接除以 zoom
        let localX = relX / zoom
        let localY = relY / zoom

        return textView.convert(CGPoint(x: localX, y: localY), to: nil)
    }
}
