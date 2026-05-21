import Foundation
import CoreGraphics

/// 磁吸瓦片对齐（Story 2.3 AC）
/// - Wall matching：节点边缘对齐到邻近节点的边缘
/// - Gap filling：填充节点间空隙
/// - 不依赖固定网格，基于实际布局自适应
struct TileSnapping {
    /// 磁吸吸附阈值（画布坐标，小于此距离时自动对齐）
    static let snapThreshold: CGFloat = 12.0

    /// 邻近过滤扩展半径（画布坐标）：仅考虑距离拖动节点此范围内的节点参与 snap
    /// 设为 snapThreshold * 50 可覆盖绝大多数合理布局间距，减少远处节点的无效计算
    private static let proximityRadius: CGFloat = 600.0

    // MARK: - 主入口

    /// 计算拖动节点的磁吸目标位置
    /// - Parameters:
    ///   - draggingFrame: 正在拖动的节点当前 frame（画布坐标）
    ///   - otherFrames: 其他所有节点的 frame（画布坐标）
    /// - Returns: 吸附后的 origin，以及参考线列表（用于 UI 显示蓝色参考线）
    static func snap(
        draggingFrame: CGRect,
        against otherFrames: [CGRect]
    ) -> (snappedOrigin: CGPoint, guidelines: [GuideLine]) {
        var x = draggingFrame.origin.x
        var y = draggingFrame.origin.y
        var guidelines: [GuideLine] = []

        let dW = draggingFrame.width
        let dH = draggingFrame.height
        let dMinX = x, dMaxX = x + dW
        let dMinY = y, dMaxY = y + dH

        var bestDX: CGFloat = snapThreshold + 1
        var bestDY: CGFloat = snapThreshold + 1

        // 预过滤：仅对距拖动节点 proximityRadius 范围内的节点做 snap 计算
        let expandedFrame = draggingFrame.insetBy(dx: -proximityRadius, dy: -proximityRadius)

        for other in otherFrames {
            // 空间过滤：跳过离拖动节点太远的节点
            guard expandedFrame.intersects(other) else { continue }
            let oMinX = other.minX, oMaxX = other.maxX
            let oMinY = other.minY, oMaxY = other.maxY

            // Wall matching X: 左/右边对齐
            let candidatesX: [(CGFloat, CGFloat, GuideAxis)] = [
                (dMinX, oMinX, .vertical),   // 左边对齐左边
                (dMinX, oMaxX, .vertical),   // 左边对齐右边
                (dMaxX, oMinX, .vertical),   // 右边对齐左边
                (dMaxX, oMaxX, .vertical),   // 右边对齐右边
            ]
            for (da, oa, axis) in candidatesX {
                let dist = abs(da - oa)
                if dist < snapThreshold && dist < bestDX {
                    bestDX = dist
                    let delta = oa - da
                    x = dMinX + delta
                    guidelines.removeAll { $0.axis == .vertical }
                    guidelines.append(GuideLine(
                        axis: axis,
                        position: oa,
                        start: min(dMinY, oMinY) - 20,
                        end: max(dMaxY, oMaxY) + 20
                    ))
                }
            }

            // Wall matching Y: 上/下边对齐
            let candidatesY: [(CGFloat, CGFloat, GuideAxis)] = [
                (dMinY, oMinY, .horizontal),
                (dMinY, oMaxY, .horizontal),
                (dMaxY, oMinY, .horizontal),
                (dMaxY, oMaxY, .horizontal),
            ]
            for (da, oa, axis) in candidatesY {
                let dist = abs(da - oa)
                if dist < snapThreshold && dist < bestDY {
                    bestDY = dist
                    let delta = oa - da
                    y = dMinY + delta
                    guidelines.removeAll { $0.axis == .horizontal }
                    guidelines.append(GuideLine(
                        axis: axis,
                        position: oa,
                        start: min(dMinX, oMinX) - 20,
                        end: max(dMaxX, oMaxX) + 20
                    ))
                }
            }
        }
        return (CGPoint(x: x, y: y), guidelines)
    }
}

// MARK: - 参考线数据

enum GuideAxis { case horizontal, vertical }

struct GuideLine {
    let axis: GuideAxis
    let position: CGFloat   // x（竖线）或 y（横线）
    let start: CGFloat      // 线段起点
    let end: CGFloat        // 线段终点
}
