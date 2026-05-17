import Foundation
import CoreGraphics

/// 悬链线（Catenary）物理模拟
/// - 21 个控制点，弯曲比 1.08~1.15
/// - 重力方向沿 Y+（屏幕向下）
final class RopeSimulation {
    static let controlPointCount = Constants.ropeControlPointCount

    /// 计算悬链线控制点
    /// - Parameters:
    ///   - start: 起点（画布坐标）
    ///   - end: 终点（画布坐标）
    /// - Returns: 21 个控制点数组
    func compute(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let count = RopeSimulation.controlPointCount
        let dx = end.x - start.x
        let dy = end.y - start.y
        let dist = sqrt(dx * dx + dy * dy)

        // 弯曲量：绳长 = dist * bendRatio
        let bendRatio = Constants.ropeBendRatioMin + (Constants.ropeBendRatioMax - Constants.ropeBendRatioMin) * 0.5
        let sag = dist * (bendRatio - 1.0) * 0.5

        return (0..<count).map { i in
            let t = CGFloat(i) / CGFloat(count - 1)
            // 线性插值基础位置
            let x = start.x + dx * t
            let y = start.y + dy * t
            // 悬链线下垂：抛物线近似（在两端为 0，中点最大）
            let droop = sag * 4 * t * (1 - t)
            return CGPoint(x: x, y: y + droop)
        }
    }

    /// 将控制点数组序列化为 [[Double]] 格式（用于 workspace.json）
    func serialize(_ points: [CGPoint]) -> [[Double]] {
        points.map { [Double($0.x), Double($0.y)] }
    }

    /// 从 [[Double]] 反序列化
    func deserialize(_ raw: [[Double]]) -> [CGPoint] {
        raw.compactMap { arr in
            guard arr.count >= 2 else { return nil }
            return CGPoint(x: arr[0], y: arr[1])
        }
    }
}
