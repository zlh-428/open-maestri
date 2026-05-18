import SwiftUI

// MARK: - 画布缩略图弹层

struct CanvasMinimapPopover: View {
    let nodes: [CanvasNode]
    let canvasOrigin: CGPoint
    let zoom: CGFloat
    let onJumpTo: (CGPoint) -> Void

    /// 缩略图固定尺寸
    private let mapSize = CGSize(width: 280, height: 180)

    var body: some View {
        VStack(spacing: 0) {
            if nodes.isEmpty {
                Text("画布为空")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: mapSize.width, height: mapSize.height)
            } else {
                minimapCanvas
            }
        }
        .padding(12)
    }

    private var minimapCanvas: some View {
        let bounds = computeBounds()
        let scale = computeScale(bounds: bounds)

        return ZStack(alignment: .topLeading) {
            // 浅灰背景（画布区域）
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.96))
                .frame(width: mapSize.width, height: mapSize.height)

            // 节点色块
            ForEach(nodes, id: \.id) { node in
                let rect = scaledRect(for: node.frame, bounds: bounds, scale: scale)
                Button {
                    // 点击节点 → 将画布定位使该节点居中
                    let viewportW: CGFloat = 800 / zoom
                    let viewportH: CGFloat = 600 / zoom
                    let target = CGPoint(
                        x: node.frame.midX - viewportW / 2,
                        y: node.frame.midY - viewportH / 2
                    )
                    onJumpTo(target)
                } label: {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(nodeColor(for: node.content))
                        .frame(width: max(rect.width, 6), height: max(rect.height, 4))
                        .offset(x: rect.minX, y: rect.minY)
                }
                .buttonStyle(.plain)
            }

            // 当前视口指示框
            let viewportRect = scaledViewportRect(bounds: bounds, scale: scale)
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.blue.opacity(0.6), lineWidth: 1.5)
                .frame(width: viewportRect.width, height: viewportRect.height)
                .offset(x: viewportRect.minX, y: viewportRect.minY)
        }
        .frame(width: mapSize.width, height: mapSize.height)
        .clipped()
    }

    // MARK: - 坐标计算

    /// 计算所有节点的包围盒（含一些 padding）
    private func computeBounds() -> CGRect {
        guard !nodes.isEmpty else { return .zero }
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for node in nodes {
            minX = min(minX, node.frame.minX)
            minY = min(minY, node.frame.minY)
            maxX = max(maxX, node.frame.maxX)
            maxY = max(maxY, node.frame.maxY)
        }
        // 添加 padding
        let pad: CGFloat = 100
        return CGRect(x: minX - pad, y: minY - pad,
                      width: maxX - minX + pad * 2,
                      height: maxY - minY + pad * 2)
    }

    /// 计算缩放比例（保持纵横比 fit 到 mapSize）
    private func computeScale(bounds: CGRect) -> CGFloat {
        guard bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(mapSize.width / bounds.width, mapSize.height / bounds.height)
    }

    /// 将画布坐标映射到缩略图坐标
    private func scaledRect(for frame: CGRect, bounds: CGRect, scale: CGFloat) -> CGRect {
        let x = (frame.minX - bounds.minX) * scale
        let y = (frame.minY - bounds.minY) * scale
        let w = frame.width * scale
        let h = frame.height * scale
        // 居中偏移
        let totalW = bounds.width * scale
        let totalH = bounds.height * scale
        let offsetX = (mapSize.width - totalW) / 2
        let offsetY = (mapSize.height - totalH) / 2
        return CGRect(x: x + offsetX, y: y + offsetY, width: w, height: h)
    }

    /// 当前视口在缩略图中的位置
    private func scaledViewportRect(bounds: CGRect, scale: CGFloat) -> CGRect {
        let vpW: CGFloat = 800 / zoom  // 估算视口宽度
        let vpH: CGFloat = 600 / zoom  // 估算视口高度
        let vpFrame = CGRect(x: canvasOrigin.x, y: canvasOrigin.y, width: vpW, height: vpH)
        return scaledRect(for: vpFrame, bounds: bounds, scale: scale)
    }

    /// 根据节点类型返回对应颜色（与截图一致）
    private func nodeColor(for content: NodeContent) -> Color {
        switch content {
        case .terminal:
            return Color.blue                          // 蓝色（终端）
        case .stickyNote:
            return Color(red: 0.6, green: 0.88, blue: 0.88)  // 浅青色（笔记）
        case .portal:
            return Color(red: 1.0, green: 0.92, blue: 0.6)   // 浅黄色（Portal）
        case .fileTree:
            return Color(red: 1.0, green: 0.82, blue: 0.6)   // 浅橙色（文件树）
        case .text:
            return Color(red: 0.7, green: 0.7, blue: 0.9)    // 浅紫色（文本标签）
        case .drawing:
            return Color(red: 0.9, green: 0.75, blue: 0.85)  // 浅粉色（手绘）
        }
    }
}
