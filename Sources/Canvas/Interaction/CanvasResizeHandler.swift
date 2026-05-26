import AppKit

extension CanvasViewportView {

    // MARK: - Resize 辅助

    func applyResizeOnCanvas(id: UUID,
                             edge: ResizeEdge,
                             dx: CGFloat, dy: CGFloat,
                             startFrame: CGRect) {
        let minW = CanvasNodeConstants.minNodeWidth * zoom
        let minH = CanvasNodeConstants.minNodeHeight * zoom
        let grid = Constants.canvasGridSpacing

        var x = startFrame.origin.x
        var y = startFrame.origin.y
        var w = startFrame.width
        var h = startFrame.height

        // startFrame 是屏幕坐标（缩放后），dx/dy 亦为屏幕坐标
        // isFlipped = true：y=0 在顶部，dy>0 向下
        switch edge {
        case .right:
            w = max(w + dx, minW)
        case .left:
            let newW = max(w - dx, minW)
            x = startFrame.maxX - newW
            w = newW
        case .bottom:
            h = max(h + dy, minH)
        case .top:
            let bottom = y + h
            let newH = max(h - dy, minH)
            y = bottom - newH
            h = newH
        case .bottomLeft:
            let newW = max(w - dx, minW)
            x = startFrame.maxX - newW
            w = newW
            h = max(h + dy, minH)
        case .bottomRight:
            w = max(w + dx, minW)
            h = max(h + dy, minH)
        case .topLeft:
            let newW = max(w - dx, minW)
            x = startFrame.maxX - newW
            w = newW
            let bottom = y + h
            let newH = max(h - dy, minH)
            y = bottom - newH
            h = newH
        case .topRight:
            w = max(w + dx, minW)
            let bottom = y + h
            let newH = max(h - dy, minH)
            y = bottom - newH
            h = newH
        }

        // 将活动边吸附到画布网格（与拖拽/绘制保持一致）
        // 先转为画布坐标取整，再转回屏幕坐标
        let rawCanvasOrigin = screenToCanvas(CGPoint(x: x, y: y))
        let rawCanvasW = w / zoom
        let rawCanvasH = h / zoom

        let snappedCanvasOrigin: CGPoint
        let snappedCanvasW: CGFloat
        let snappedCanvasH: CGFloat

        switch edge {
        case .right, .bottomRight, .topRight:
            // 右边活动：吸附右边
            let snappedRight = ((rawCanvasOrigin.x + rawCanvasW) / grid).rounded() * grid
            snappedCanvasW = max(snappedRight - rawCanvasOrigin.x, CanvasNodeConstants.minNodeWidth)
            snappedCanvasOrigin = rawCanvasOrigin
            snappedCanvasH = rawCanvasH
        case .left, .bottomLeft, .topLeft:
            // 左边活动：吸附左边（右边固定）
            let fixedRight = rawCanvasOrigin.x + rawCanvasW
            let snappedLeft = (rawCanvasOrigin.x / grid).rounded() * grid
            snappedCanvasW = max(fixedRight - snappedLeft, CanvasNodeConstants.minNodeWidth)
            snappedCanvasOrigin = CGPoint(x: fixedRight - snappedCanvasW, y: rawCanvasOrigin.y)
            snappedCanvasH = rawCanvasH
        case .bottom:
            // 下边活动：吸附下边
            let snappedBottom = ((rawCanvasOrigin.y + rawCanvasH) / grid).rounded() * grid
            snappedCanvasH = max(snappedBottom - rawCanvasOrigin.y, CanvasNodeConstants.minNodeHeight)
            snappedCanvasOrigin = rawCanvasOrigin
            snappedCanvasW = rawCanvasW
        case .top:
            // 上边活动：吸附上边（下边固定）
            let fixedBottom = rawCanvasOrigin.y + rawCanvasH
            let snappedTop = (rawCanvasOrigin.y / grid).rounded() * grid
            snappedCanvasH = max(fixedBottom - snappedTop, CanvasNodeConstants.minNodeHeight)
            snappedCanvasOrigin = CGPoint(x: rawCanvasOrigin.x, y: fixedBottom - snappedCanvasH)
            snappedCanvasW = rawCanvasW
        }

        let newCanvasFrame = CGRect(x: snappedCanvasOrigin.x, y: snappedCanvasOrigin.y,
                                    width: snappedCanvasW, height: snappedCanvasH)

        // 网格跨越时触发触觉反馈（与拖拽/绘制一致）
        if let prev = nodeCanvasFrames[id], prev != newCanvasFrame {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        nodeCanvasFrames[id] = newCanvasFrame
        // 同步更新 currentNodes，避免 layout() 重建 SwiftUI 视图时使用旧 frame 导致"弹回"
        updateNodeFrameInPlace(id: id, frame: newCanvasFrame)
        CATransaction.commit()
        needsLayout = true
        // 通知连线物理引擎：resize 也改变了节点中心
        onNodeFramesDuringDrag?([id])
    }
}
