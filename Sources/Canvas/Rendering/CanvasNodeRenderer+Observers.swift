import AppKit
import SwiftUI

// MARK: - Notification Observers

extension CanvasNodeRenderer {

    func setupActivationObserver() {
        let obs = NotificationCenter.default.addObserver(
            forName: .canvasNodeActivated, object: nil, queue: .main
        ) { [weak self] notif in
            guard let id = notif.userInfo?["nodeId"] as? UUID else { return }
            if let provider = TerminalManager.shared.providers[id],
               let tv = provider.terminalView {
                tv.window?.makeFirstResponder(tv)
            }
            // Portal 节点不在此处聚焦——由 CanvasInteractionHandler 根据点击位置精确判断
        }
        notificationObservers.append(obs)
    }

    func setupSelectionObserver() {
        let obs = NotificationCenter.default.addObserver(
            forName: .canvasSelectionChanged, object: nil, queue: .main
        ) { [weak self] notif in
            guard let self,
                  let canvas = self.canvas,
                  let ids = notif.userInfo?["selectedIds"] as? Set<UUID> else { return }
            guard let current = self.nodesHostingView?.rootView else { return }
            // 注意：不能仅凭 selectedNodeIds 不变就跳过——zIndex 变化时节点排序已更新，
            // 必须用最新的 viewportCulledNodes() 重建 rootView 才能让渲染层反映新层级顺序
            let lockedIds = Set(canvas.currentNodes.filter { $0.isLocked }.map { $0.id })
            self.nodesHostingView?.rootView = CanvasNodesSwiftUIView(
                nodes: canvas.viewportCulledNodes(),
                canvasOrigin: canvas.canvasOrigin,
                zoom: canvas.zoom,
                selectedNodeIds: ids,
                lockedNodeIds: lockedIds,
                workspace: current.workspace,
                dropTargetNodeId: current.dropTargetNodeId,
                onActivated: current.onActivated,
                onClose: current.onClose,
                onRename: current.onRename,
                onDuplicate: current.onDuplicate,
                onLockToggle: current.onLockToggle
            )
        }
        notificationObservers.append(obs)
    }

    func setupDropTargetObserver() {
        let obs = NotificationCenter.default.addObserver(
            forName: .canvasDropTargetChanged, object: nil, queue: .main
        ) { [weak self] notif in
            guard let self,
                  let canvas = self.canvas else { return }
            let dropTargetId = notif.userInfo?["dropTargetNodeId"] as? UUID
            guard let current = self.nodesHostingView?.rootView,
                  current.dropTargetNodeId != dropTargetId else { return }
            self.nodesHostingView?.rootView = CanvasNodesSwiftUIView(
                nodes: canvas.viewportCulledNodes(),
                canvasOrigin: canvas.canvasOrigin,
                zoom: canvas.zoom,
                selectedNodeIds: current.selectedNodeIds,
                lockedNodeIds: current.lockedNodeIds,
                workspace: current.workspace,
                dropTargetNodeId: dropTargetId,
                onActivated: current.onActivated,
                onClose: current.onClose,
                onRename: current.onRename,
                onDuplicate: current.onDuplicate,
                onLockToggle: current.onLockToggle
            )
        }
        notificationObservers.append(obs)
    }

    func setupNodeStateObservers() {
        // 节点 isLocked 变更：同步到 canvas.currentNodes
        let lockObs = NotificationCenter.default.addObserver(
            forName: .canvasNodeLockChanged, object: nil, queue: .main
        ) { [weak self] notif in
            guard let id = notif.userInfo?["nodeId"] as? UUID,
                  let locked = notif.userInfo?["isLocked"] as? Bool else { return }
            self?.canvas?.updateNodeLockedInPlace(id: id, isLocked: locked)
        }
        notificationObservers.append(lockObs)

        // 节点 content 变更：同步到 canvas.currentNodes
        let contentObs = NotificationCenter.default.addObserver(
            forName: .canvasNodeContentChanged, object: nil, queue: .main
        ) { [weak self] notif in
            guard let self,
                  let id = notif.userInfo?["nodeId"] as? UUID,
                  let content = notif.userInfo?["content"] as? NodeContent else { return }
            canvas?.updateNodeContentInPlace(id: id, content: content)
            // 若携带新 frame（文本节点内容/样式变化时自动测量），同步更新画布 frame
            if let newFrame = notif.userInfo?["frame"] as? CGRect {
                canvas?.updateNodeFrameInPlace(id: id, frame: newFrame)
                canvas?.nodeCanvasFrames[id] = newFrame
            }
            // displayName 同步
            if case .terminal(let tc) = content {
                TerminalManager.shared.terminals[id]?.displayName = tc.name
            }
            // 刷新 SwiftUI 节点层
            guard let canvas, let current = nodesHostingView?.rootView else { return }
            let lockedIds = Set(canvas.currentNodes.filter { $0.isLocked }.map { $0.id })
            nodesHostingView?.rootView = CanvasNodesSwiftUIView(
                nodes: canvas.viewportCulledNodes(),
                canvasOrigin: canvas.canvasOrigin,
                zoom: canvas.zoom,
                selectedNodeIds: canvas.selectedNodeIds,
                lockedNodeIds: lockedIds,
                workspace: current.workspace,
                dropTargetNodeId: current.dropTargetNodeId,
                onActivated: current.onActivated,
                onClose: current.onClose,
                onRename: current.onRename,
                onDuplicate: current.onDuplicate,
                onLockToggle: current.onLockToggle
            )
        }
        notificationObservers.append(contentObs)

        // 连接状态变化（ask 通信开始/结束）：立即重建状态缓存并重渲染连接线
        let connStatusObs = NotificationCenter.default.addObserver(
            forName: .connectionStatusChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuildConnectionStatusCache()
            self?.rerenderConnections()
        }
        notificationObservers.append(connStatusObs)
    }
}
