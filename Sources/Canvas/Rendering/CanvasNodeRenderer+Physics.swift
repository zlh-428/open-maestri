import AppKit
import CoreGraphics

// MARK: - Connection Physics & Rendering

extension CanvasNodeRenderer {

    /// 初始化物理模拟回调（在 setupOverlay 后调用一次）
    func setupPhysicsCallbacks() {
        ropeSimulation.onTick = { [weak self] allPoints in
            self?.renderConnectionsFromPhysics(allPoints)
        }
        ropeSimulation.onSleep = { [weak self] allPoints in
            self?.renderConnectionsFromPhysics(allPoints)
        }
    }

    /// 共享的物理回调渲染方法：将画布坐标控制点转为屏幕坐标并推送给 overlay
    func renderConnectionsFromPhysics(_ allPoints: [UUID: [CGPoint]]) {
        guard let overlay = overlayView, let canvas else { return }
        var renderables: [RenderableConnection] = []
        for meta in activeConnections {
            guard let canvasPoints = allPoints[meta.id] else { continue }
            let screenPoints = canvasPoints.map { canvas.canvasToScreen($0) }
            let status = connectionStatusCache[meta.id] ?? .idle
            renderables.append(RenderableConnection(id: meta.id, screenPoints: screenPoints, status: status))
        }
        overlay.connections = renderables
    }

    /// 轻量级重渲染：仅将已有的物理控制点重新转换为屏幕坐标
    /// 用于 viewport pan/zoom 变化时（节点画布坐标不变，只有屏幕映射变了）
    func rerenderConnections() {
        renderConnectionsFromPhysics(ropeSimulation.allPoints())
    }

    /// 同步连接列表 + 更新物理端点
    /// 调用时机：节点/连接数量变化、zoom/pan 变化、节点拖动中
    func syncConnections(workspace: WorkspaceManager) {
        guard let overlay = overlayView, let canvas else { return }

        var metas: [ConnectionMeta] = []
        var activeIds: Set<UUID> = []
        var anchorUpdates: [(id: UUID, anchorA: CGPoint, anchorB: CGPoint)] = []

        // 收集所有连接的端点（计算边缘锚点，而非中心点）
        for conn in workspace.connections {
            guard let frameA = liveNodeFrame(id: conn.terminalIdA, in: workspace),
                  let frameB = liveNodeFrame(id: conn.terminalIdB, in: workspace) else { continue }
            let centerB = CGPoint(x: frameB.midX, y: frameB.midY)
            let centerA = CGPoint(x: frameA.midX, y: frameA.midY)
            let anchorA = edgeAnchor(of: frameA, toward: centerB)
            let anchorB = edgeAnchor(of: frameB, toward: centerA)
            activeIds.insert(conn.id)
            metas.append(ConnectionMeta(id: conn.id, nodeIdA: conn.terminalIdA, nodeIdB: conn.terminalIdB))
            anchorUpdates.append((id: conn.id, anchorA: anchorA, anchorB: anchorB))
        }

        for conn in workspace.noteConnections {
            guard let frameA = liveNodeFrame(id: conn.terminalId, in: workspace),
                  let frameB = liveNodeFrame(id: conn.noteNodeId, in: workspace) else { continue }
            let centerB = CGPoint(x: frameB.midX, y: frameB.midY)
            let centerA = CGPoint(x: frameA.midX, y: frameA.midY)
            let anchorA = edgeAnchor(of: frameA, toward: centerB)
            let anchorB = edgeAnchor(of: frameB, toward: centerA)
            activeIds.insert(conn.id)
            metas.append(ConnectionMeta(id: conn.id, nodeIdA: conn.terminalId, nodeIdB: conn.noteNodeId))
            anchorUpdates.append((id: conn.id, anchorA: anchorA, anchorB: anchorB))
        }

        for conn in workspace.portalConnections {
            guard let frameA = liveNodeFrame(id: conn.terminalId, in: workspace),
                  let frameB = liveNodeFrame(id: conn.portalNodeId, in: workspace) else { continue }
            let centerB = CGPoint(x: frameB.midX, y: frameB.midY)
            let centerA = CGPoint(x: frameA.midX, y: frameA.midY)
            let anchorA = edgeAnchor(of: frameA, toward: centerB)
            let anchorB = edgeAnchor(of: frameB, toward: centerA)
            activeIds.insert(conn.id)
            metas.append(ConnectionMeta(id: conn.id, nodeIdA: conn.terminalId, nodeIdB: conn.portalNodeId))
            anchorUpdates.append((id: conn.id, anchorA: anchorA, anchorB: anchorB))
        }

        for conn in workspace.noteToNoteConnections {
            guard let frameA = liveNodeFrame(id: conn.noteNodeIdA, in: workspace),
                  let frameB = liveNodeFrame(id: conn.noteNodeIdB, in: workspace) else { continue }
            let centerB = CGPoint(x: frameB.midX, y: frameB.midY)
            let centerA = CGPoint(x: frameA.midX, y: frameA.midY)
            let anchorA = edgeAnchor(of: frameA, toward: centerB)
            let anchorB = edgeAnchor(of: frameB, toward: centerA)
            activeIds.insert(conn.id)
            metas.append(ConnectionMeta(id: conn.id, nodeIdA: conn.noteNodeIdA, nodeIdB: conn.noteNodeIdB))
            anchorUpdates.append((id: conn.id, anchorA: anchorA, anchorB: anchorB))
        }

        for conn in workspace.portalToPortalConnections {
            guard let frameA = liveNodeFrame(id: conn.portalIdA, in: workspace),
                  let frameB = liveNodeFrame(id: conn.portalIdB, in: workspace) else { continue }
            let centerB = CGPoint(x: frameB.midX, y: frameB.midY)
            let centerA = CGPoint(x: frameA.midX, y: frameA.midY)
            let anchorA = edgeAnchor(of: frameA, toward: centerB)
            let anchorB = edgeAnchor(of: frameB, toward: centerA)
            activeIds.insert(conn.id)
            metas.append(ConnectionMeta(id: conn.id, nodeIdA: conn.portalIdA, nodeIdB: conn.portalIdB))
            anchorUpdates.append((id: conn.id, anchorA: anchorA, anchorB: anchorB))
        }

        // 更新活跃连接元数据
        activeConnections = metas

        // 清理已删除的绳索
        let existingIds = Set(ropeSimulation.ropes.keys)
        for deadId in existingIds.subtracting(activeIds) {
            ropeSimulation.removeRope(id: deadId)
        }

        // 添加新绳索 / 更新已有绳索的端点
        for update in anchorUpdates {
            if ropeSimulation.ropes[update.id] != nil {
                ropeSimulation.updateAnchors(id: update.id, anchorA: update.anchorA, anchorB: update.anchorB)
            } else {
                ropeSimulation.addRope(id: update.id, anchorA: update.anchorA, anchorB: update.anchorB)
            }
        }

        // 构建连接状态缓存（O(n) 一次，后续物理回调 O(1) 查询）
        rebuildConnectionStatusCache()

        // 立即渲染当前帧（确保连线可见，不论物理是否在运行）
        var renderables: [RenderableConnection] = []
        for meta in metas {
            guard let canvasPoints = ropeSimulation.points(for: meta.id) else { continue }
            let screenPoints = canvasPoints.map { canvas.canvasToScreen($0) }
            let status = connectionStatusCache[meta.id] ?? .idle
            renderables.append(RenderableConnection(id: meta.id, screenPoints: screenPoints, status: status))
        }
        overlay.connections = renderables
    }

    /// 获取节点的实时 frame（优先使用 canvas 中的拖拽实时值，否则从 workspace 取）
    func liveNodeFrame(id: UUID, in workspace: WorkspaceManager) -> CGRect? {
        if let liveFrame = canvas?.nodeCanvasFrames[id] {
            return liveFrame
        }
        return workspace.nodes.first { $0.id == id }?.frame
    }

    // MARK: - 边缘锚点计算

    /// 计算连接线锚点：从节点 frame 的中心出发，向目标中心方向与边框的交点
    func edgeAnchor(of frame: CGRect, toward target: CGPoint) -> CGPoint {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let dx = target.x - center.x
        let dy = target.y - center.y

        guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return center }

        let halfW = frame.width / 2.0
        let halfH = frame.height / 2.0

        var t: CGFloat = .greatestFiniteMagnitude

        if abs(dx) > 0.001 {
            let tx = halfW / abs(dx)
            if tx < t { t = tx }
        }
        if abs(dy) > 0.001 {
            let ty = halfH / abs(dy)
            if ty < t { t = ty }
        }

        return CGPoint(x: center.x + dx * t, y: center.y + dy * t)
    }

    /// 重建连接状态缓存（从 ConnectionManager 的活跃连接中构建 [connectionId: status] 字典）
    func rebuildConnectionStatusCache() {
        var cache: [UUID: ConnectionStatus] = [:]
        for meta in activeConnections {
            if let active = ConnectionManager.shared.connections[meta.id] {
                cache[meta.id] = active.status
            } else {
                let matched = ConnectionManager.shared.connections.values
                    .first { $0.nodeIdA == meta.nodeIdA && $0.nodeIdB == meta.nodeIdB }
                cache[meta.id] = matched?.status ?? .idle
            }
        }
        connectionStatusCache = cache
    }

    /// 拖动中增量更新：只更新涉及被拖动节点的绳索端点
    func updatePhysicsAnchorsForNodes(_ movedNodeIds: Set<UUID>, workspace: WorkspaceManager) {
        var updates: [(id: UUID, anchorA: CGPoint, anchorB: CGPoint)] = []

        for meta in activeConnections {
            guard movedNodeIds.contains(meta.nodeIdA) || movedNodeIds.contains(meta.nodeIdB) else { continue }
            guard let frameA = liveNodeFrame(id: meta.nodeIdA, in: workspace),
                  let frameB = liveNodeFrame(id: meta.nodeIdB, in: workspace) else { continue }
            let centerA = CGPoint(x: frameA.midX, y: frameA.midY)
            let centerB = CGPoint(x: frameB.midX, y: frameB.midY)
            let anchorA = edgeAnchor(of: frameA, toward: centerB)
            let anchorB = edgeAnchor(of: frameB, toward: centerA)
            updates.append((id: meta.id, anchorA: anchorA, anchorB: anchorB))
        }

        if !updates.isEmpty {
            ropeSimulation.updateAnchors(updates: updates)
            renderConnectionsFromPhysics(ropeSimulation.allPoints())
        }
    }
}
