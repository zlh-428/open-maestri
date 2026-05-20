import Foundation
import CoreGraphics

// MARK: - Rope（单条绳索的物理状态）

/// 单条物理绳索：存储 21 个质点的位置和上一帧位置（Verlet 积分所需）
final class Rope {
    let id: UUID
    /// 当前帧各质点位置（画布坐标）
    var points: [CGPoint]
    /// 上一帧各质点位置（Verlet 积分用于计算速度）
    var prevPoints: [CGPoint]
    /// 绳索两端锚点（连接到节点中心）
    var anchorA: CGPoint
    var anchorB: CGPoint
    /// 绳段静止长度（每两个相邻质点之间的理想距离）
    var segmentLength: CGFloat

    init(id: UUID, anchorA: CGPoint, anchorB: CGPoint, pointCount: Int = Constants.ropeControlPointCount) {
        self.id = id
        self.anchorA = anchorA
        self.anchorB = anchorB

        // 初始化为直线均分
        var pts: [CGPoint] = []
        for i in 0..<pointCount {
            let t = CGFloat(i) / CGFloat(pointCount - 1)
            pts.append(CGPoint(
                x: anchorA.x + (anchorB.x - anchorA.x) * t,
                y: anchorA.y + (anchorB.y - anchorA.y) * t
            ))
        }
        self.points = pts
        self.prevPoints = pts

        // 绳段长度 = 绳总长度 / (点数-1)，绳总长度 = 直线距离 * bendRatio
        let dist = hypot(anchorB.x - anchorA.x, anchorB.y - anchorA.y)
        let bendRatio = (Constants.ropeBendRatioMin + Constants.ropeBendRatioMax) / 2.0
        let ropeLength = max(dist * bendRatio, 20.0)  // 最小绳长，避免零长度
        self.segmentLength = ropeLength / CGFloat(pointCount - 1)
    }

    /// 重置绳索到新端点位置（直线初始化）
    func reset(anchorA: CGPoint, anchorB: CGPoint) {
        self.anchorA = anchorA
        self.anchorB = anchorB
        let count = points.count
        for i in 0..<count {
            let t = CGFloat(i) / CGFloat(count - 1)
            let pt = CGPoint(
                x: anchorA.x + (anchorB.x - anchorA.x) * t,
                y: anchorA.y + (anchorB.y - anchorA.y) * t
            )
            points[i] = pt
            prevPoints[i] = pt
        }
        updateSegmentLength()
    }

    /// 更新端点后重算绳段长度（保持自然下垂比例）
    func updateSegmentLength() {
        let dist = hypot(anchorB.x - anchorA.x, anchorB.y - anchorA.y)
        let bendRatio = (Constants.ropeBendRatioMin + Constants.ropeBendRatioMax) / 2.0
        let ropeLength = max(dist * bendRatio, 20.0)
        segmentLength = ropeLength / CGFloat(points.count - 1)
    }
}

// MARK: - RopeSimulation（物理模拟引擎）

/// 悬链线物理模拟器（对标 Maestri RopeSimulation）
/// - Verlet 积分 + 弹簧距离约束 + 重力
/// - Timer 驱动 60fps 物理 tick（Timer 挂在 RunLoop.main，回调始终在主线程）
/// - 自动睡眠：运动量 < 阈值时停止模拟，节省 CPU
/// - 唤醒：端点位置变化时重新启动模拟
///
/// 线程模型：所有访问均应在主线程（由 @MainActor CanvasNodeRenderer 保证）。
/// Timer 的 RunLoop.main 调度也确保 tick() 在主线程执行。
final class RopeSimulation {
    static let controlPointCount = Constants.ropeControlPointCount

    // MARK: - 物理参数

    /// 重力加速度（画布坐标单位/帧²），Y+ 向下
    private static let gravity: CGFloat = 0.8
    /// 阻尼系数（0~1，越大越快衰减，0.98 = 2% 每帧速度损失）
    private static let damping: CGFloat = 0.98
    /// 距离约束迭代次数（越多越刚性，3~5 次较优）
    private static let constraintIterations = 5
    /// 睡眠阈值：当所有质点单帧总运动量 < 此值时进入睡眠
    private static let sleepThreshold: CGFloat = 0.1
    /// 唤醒阈值：端点偏移 > 此值时唤醒
    private static let wakeThreshold: CGFloat = 0.5
    /// 物理 tick 间隔（秒），约 60fps
    private static let tickInterval: TimeInterval = 1.0 / 60.0

    // MARK: - 状态

    /// 所有参与物理模拟的绳索
    private(set) var ropes: [UUID: Rope] = [:]
    /// 物理定时器
    private var timer: Timer?
    /// 是否处于睡眠状态（所有绳索均静止）
    private(set) var isSleeping: Bool = true
    /// 当前帧总运动量
    private var totalMovement: CGFloat = 0
    /// 睡眠回调（物理停止后调用，用于持久化 ropePoints）
    var onSleep: (([UUID: [CGPoint]]) -> Void)?
    /// 每帧更新回调（用于实时更新渲染层）
    var onTick: (([UUID: [CGPoint]]) -> Void)?

    // MARK: - 生命周期

    deinit {
        stopTimer()
    }

    // MARK: - 公开接口

    /// 添加绳索（创建连接时调用）
    func addRope(id: UUID, anchorA: CGPoint, anchorB: CGPoint) {
        let rope = Rope(id: id, anchorA: anchorA, anchorB: anchorB)
        ropes[id] = rope
        wake()
    }

    /// 从已有控制点恢复绳索（加载 workspace 时）
    func addRope(id: UUID, anchorA: CGPoint, anchorB: CGPoint, existingPoints: [CGPoint]) {
        let rope = Rope(id: id, anchorA: anchorA, anchorB: anchorB)
        if existingPoints.count == rope.points.count {
            rope.points = existingPoints
            rope.prevPoints = existingPoints
        }
        ropes[id] = rope
        // 恢复时不立即唤醒（假设已处于稳态）
    }

    /// 移除绳索（断开连接时调用）
    func removeRope(id: UUID) {
        ropes.removeValue(forKey: id)
        if ropes.isEmpty {
            sleep()
        }
    }

    /// 更新绳索端点（节点拖动时实时调用）
    /// 端点变化超过阈值时唤醒物理模拟
    func updateAnchors(id: UUID, anchorA: CGPoint, anchorB: CGPoint) {
        guard let rope = ropes[id] else { return }
        let movedA = hypot(rope.anchorA.x - anchorA.x, rope.anchorA.y - anchorA.y)
        let movedB = hypot(rope.anchorB.x - anchorB.x, rope.anchorB.y - anchorB.y)

        rope.anchorA = anchorA
        rope.anchorB = anchorB
        // 立即同步首尾质点位置到新锚点（确保渲染时端点紧贴节点边缘）
        rope.points[0] = anchorA
        rope.prevPoints[0] = anchorA
        rope.points[rope.points.count - 1] = anchorB
        rope.prevPoints[rope.points.count - 1] = anchorB
        rope.updateSegmentLength()

        // 端点移动时唤醒物理模拟
        if movedA > Self.wakeThreshold || movedB > Self.wakeThreshold {
            wake()
        }
    }

    /// 批量更新多条绳索的端点（高效路径：节点拖动影响多条连接时）
    func updateAnchors(updates: [(id: UUID, anchorA: CGPoint, anchorB: CGPoint)]) {
        var needWake = false
        for update in updates {
            guard let rope = ropes[update.id] else { continue }
            let movedA = hypot(rope.anchorA.x - update.anchorA.x, rope.anchorA.y - update.anchorA.y)
            let movedB = hypot(rope.anchorB.x - update.anchorB.x, rope.anchorB.y - update.anchorB.y)
            rope.anchorA = update.anchorA
            rope.anchorB = update.anchorB
            // 立即同步首尾质点位置到新锚点
            rope.points[0] = update.anchorA
            rope.prevPoints[0] = update.anchorA
            rope.points[rope.points.count - 1] = update.anchorB
            rope.prevPoints[rope.points.count - 1] = update.anchorB
            rope.updateSegmentLength()
            if movedA > Self.wakeThreshold || movedB > Self.wakeThreshold {
                needWake = true
            }
        }
        if needWake { wake() }
    }

    /// 获取指定绳索的当前控制点（用于渲染）
    func points(for id: UUID) -> [CGPoint]? {
        ropes[id]?.points
    }

    /// 获取所有绳索的当前控制点
    func allPoints() -> [UUID: [CGPoint]] {
        var result: [UUID: [CGPoint]] = [:]
        for (id, rope) in ropes {
            result[id] = rope.points
        }
        return result
    }

    /// 强制唤醒（外部可在需要时调用，如连接刚创建）
    func wake() {
        guard isSleeping else { return }
        isSleeping = false
        startTimer()
    }

    /// 强制停止所有模拟
    func stopAll() {
        sleep()
        ropes.removeAll()
    }

    // MARK: - 静态计算（用于不需要动画的场景，如截图/初始化）

    /// 静态计算悬链线控制点（无物理动画，即时返回）
    /// 用于：截图渲染、临时连线（拖拽创建中）
    ///
    /// - Important: 下垂方向固定为 Y+（假设 isFlipped = true，即 Y 轴向下）。
    ///   如果在非 flipped 坐标系中使用，需要对 droop 取反。
    static func computeStaticCatenary(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let count = controlPointCount
        let dx = end.x - start.x
        let dy = end.y - start.y
        let dist = hypot(dx, dy)

        let bendRatio = (Constants.ropeBendRatioMin + Constants.ropeBendRatioMax) / 2.0
        let sag = dist * (bendRatio - 1.0) * 1.5  // 自然下垂幅度

        guard dist > 1 else {
            return Array(repeating: start, count: count)
        }

        return (0..<count).map { i in
            let t = CGFloat(i) / CGFloat(count - 1)
            let x = start.x + dx * t
            let y = start.y + dy * t
            // 抛物线下垂：4*sag*t*(1-t) 在 t=0.5 时最大值为 sag
            let droop = 4.0 * sag * t * (1.0 - t)
            return CGPoint(x: x, y: y + droop)
        }
    }

    // MARK: - 序列化

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

    // MARK: - 物理模拟核心

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func sleep() {
        isSleeping = true
        stopTimer()
        // 通知外部持久化当前状态
        onSleep?(allPoints())
    }

    /// 物理模拟一帧
    private func tick() {
        totalMovement = 0

        for (_, rope) in ropes {
            simulateRope(rope)
        }

        // 通知渲染层更新
        onTick?(allPoints())

        // 检查是否可以进入睡眠
        if totalMovement < Self.sleepThreshold {
            sleep()
        }
    }

    /// 单条绳索的物理模拟步骤
    private func simulateRope(_ rope: Rope) {
        let count = rope.points.count
        guard count >= 2 else { return }

        // --- Step 1: 记录约束前位置（用于 Step 4 准确计算运动量） ---
        // 使用 prevPoints 暂存"本帧起始位置"，后续对比约束后的最终位置
        // 注意：这里的 preConstraint 是约束前快照，与 Verlet 的 prevPoints 不同
        let preConstraintPositions: [CGPoint] = rope.points

        // --- Step 2: Verlet 积分（位移 = 当前位置 - 上帧位置 + 加速度） ---
        for i in 1..<(count - 1) {
            let current = rope.points[i]
            let prev = rope.prevPoints[i]

            // 速度 = 当前 - 上帧（Verlet 隐式速度）
            let vx = (current.x - prev.x) * Self.damping
            let vy = (current.y - prev.y) * Self.damping

            // 新位置 = 当前 + 速度 + 重力加速度
            let newX = current.x + vx
            let newY = current.y + vy + Self.gravity

            rope.prevPoints[i] = current
            rope.points[i] = CGPoint(x: newX, y: newY)
        }

        // --- Step 3: 固定端点（锚定到节点中心）---
        rope.points[0] = rope.anchorA
        rope.prevPoints[0] = rope.anchorA
        rope.points[count - 1] = rope.anchorB
        rope.prevPoints[count - 1] = rope.anchorB

        // --- Step 4: 距离约束（弹簧，保持相邻质点间距 = segmentLength）---
        for _ in 0..<Self.constraintIterations {
            applyDistanceConstraints(rope)
            // 每次迭代后重新固定端点
            rope.points[0] = rope.anchorA
            rope.points[count - 1] = rope.anchorB
        }

        // --- Step 5: 累计运动量（约束后最终位置 vs 本帧起始位置）---
        // 这样准确反映了这一帧中每个质点实际移动的距离
        for i in 1..<(count - 1) {
            let dx = rope.points[i].x - preConstraintPositions[i].x
            let dy = rope.points[i].y - preConstraintPositions[i].y
            totalMovement += abs(dx) + abs(dy)
        }
    }

    /// 距离约束：Jakobsen method
    /// 遍历相邻质点对，将它们推/拉到理想距离
    private func applyDistanceConstraints(_ rope: Rope) {
        let count = rope.points.count
        let restLength = rope.segmentLength

        for i in 0..<(count - 1) {
            let p1 = rope.points[i]
            let p2 = rope.points[i + 1]

            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let dist = hypot(dx, dy)

            guard dist > 0.001 else { continue }

            let diff = (restLength - dist) / dist
            let offsetX = dx * diff * 0.5
            let offsetY = dy * diff * 0.5

            // 端点不移动（通过 i==0 和 i==count-2 判断）
            if i != 0 {
                rope.points[i] = CGPoint(x: p1.x - offsetX, y: p1.y - offsetY)
            }
            if i + 1 != count - 1 {
                rope.points[i + 1] = CGPoint(x: p2.x + offsetX, y: p2.y + offsetY)
            }
        }
    }

    // MARK: - 旧接口兼容（供 CanvasNodeRenderer 在无动画场景使用）

    /// 计算悬链线控制点（静态，无物理动画）
    /// 保留此方法以兼容不需要动画的调用方
    func compute(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        Self.computeStaticCatenary(from: start, to: end)
    }
}
