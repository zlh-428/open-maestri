import Foundation
import CoreGraphics

/// 悬链线（Catenary）物理模拟
/// - 21 个控制点，弯曲比 1.08~1.15
/// - 重力方向沿 Y+（屏幕向下，macOS 坐标系中 Y 向上，所以 droop 为负值）
/// - 使用真实 catenary 公式 y = a·cosh((x-x0)/a) 替代简单抛物线
final class RopeSimulation {
    static let controlPointCount = Constants.ropeControlPointCount

    /// 计算悬链线控制点
    /// - Parameters:
    ///   - start: 起点（屏幕坐标）
    ///   - end: 终点（屏幕坐标）
    /// - Returns: 21 个控制点数组
    func compute(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let count = RopeSimulation.controlPointCount
        let dx = end.x - start.x
        let dy = end.y - start.y
        let dist = sqrt(dx * dx + dy * dy)

        // 弯曲量：绳长 = dist * bendRatio
        let bendRatio = Constants.ropeBendRatioMin + (Constants.ropeBendRatioMax - Constants.ropeBendRatioMin) * 0.5
        let sag = dist * (bendRatio - 1.0) * 0.5

        // 距离极短时退化为直线
        guard dist > 1 else {
            return Array(repeating: start, count: count)
        }

        return (0..<count).map { i in
            let t = CGFloat(i) / CGFloat(count - 1)
            // 线性插值基础位置
            let x = start.x + dx * t
            let y = start.y + dy * t
            // 真实 catenary 下垂：cosh 曲线近似，两端为 0，中点最大
            // catenary: droop(t) = sag * (cosh(4*(t-0.5)) - cosh(2)) / (1 - cosh(2))
            // 归一化使 droop(0) = droop(1) = 0, droop(0.5) = sag
            let coshVal = cosh(4.0 * (t - 0.5))
            let coshEnd = cosh(2.0)
            let droop = sag * (coshVal - coshEnd) / (1.0 - coshEnd)
            // macOS 坐标系 Y 向上，绳索下垂应减小 Y 值
            return CGPoint(x: x, y: y - droop)
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
