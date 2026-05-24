import SwiftUI

// MARK: - Notification Handlers

extension WorkspaceCanvasView {

    func handleMaestroRecruited(notif: Notification) {
        guard let info = notif.userInfo,
              let maestroId = info["maestroId"] as? UUID,
              var recruitNode = info["recruitNode"] as? CanvasNode,
              let conn = info["connection"] as? TerminalConnection,
              let connectedIds = info["connectedIds"] as? [UUID] else { return }

        if let maestroNode = workspace.nodes.first(where: { $0.id == maestroId }) {
            let existingCount = CGFloat(connectedIds.filter { id in
                workspace.nodes.contains { $0.id == id }
            }.count)
            let w: CGFloat = 600, h: CGFloat = 400, gap: CGFloat = 20
            recruitNode.frame = CGRect(
                x: maestroNode.frame.minX + existingCount * (w + gap),
                y: maestroNode.frame.maxY + 40,
                width: w, height: h
            )
        }

        workspace.addNode(recruitNode)
        workspace.addConnection(conn)
        Task { try? await workspace.save() }
    }

    func handlePortalCreatedViaCLI(notif: Notification) {
        guard let info = notif.userInfo,
              var portalNode = info["portalNode"] as? CanvasNode else { return }
        let callerTerminalId = info["terminalId"] as? UUID

        let defaultSize = CGSize(width: 700, height: 500)
        if let tid = callerTerminalId,
           let callerNode = workspace.nodes.first(where: { $0.id == tid }) {
            portalNode.frame = CGRect(
                x: callerNode.frame.maxX + 40,
                y: callerNode.frame.minY,
                width: defaultSize.width,
                height: defaultSize.height
            )
        } else {
            let origin = workspace.canvasOrigin
            portalNode.frame = CGRect(
                x: origin.x + 200, y: origin.y + 100,
                width: defaultSize.width, height: defaultSize.height
            )
        }

        workspace.addNode(portalNode)

        if let tid = callerTerminalId {
            let conn = ConnectionManager.shared.connectTerminalToPortal(terminalId: tid, portalNodeId: portalNode.id)
            workspace.addPortalConnection(conn)
        }

        Task { try? await workspace.save() }
    }

    func handlePortalOpenedNewWindow(notif: Notification) {
        guard let info = notif.userInfo,
              let urlString = info["url"] as? String,
              let openerPortalId = info["openerPortalId"] as? UUID else { return }

        let defaultSize = CGSize(width: 700, height: 500)
        let frame: CGRect
        if let openerNode = workspace.nodes.first(where: { $0.id == openerPortalId }) {
            frame = CGRect(
                x: openerNode.frame.maxX + 40,
                y: openerNode.frame.minY,
                width: defaultSize.width,
                height: defaultSize.height
            )
        } else {
            let origin = workspace.canvasOrigin
            frame = CGRect(
                x: origin.x + 200, y: origin.y + 100,
                width: defaultSize.width, height: defaultSize.height
            )
        }

        let portalName = nextNodeName(for: "portal")
        let pc = PortalContent(name: portalName, url: urlString)
        let newNode = CanvasNode(frame: frame, content: .portal(pc))
        workspace.addNode(newNode)

        let conn = ConnectionManager.shared.connectPortalToPortal(portalIdA: openerPortalId, portalIdB: newNode.id)
        workspace.addPortalToPortalConnection(conn)

        Task { try? await workspace.save() }
    }

    func handlePortalURLDidChange(notif: Notification) {
        guard let info = notif.userInfo,
              let portalId = info["portalId"] as? UUID,
              let url = info["url"] as? String else { return }
        // 静默更新：不修改 workspace.nodes（避免触发 @Observable → 画布重渲染 → makeNSView → 重复加载 URL）
        workspace.updatePortalURLSilently(portalId: portalId, url: url)
        Task { try? await workspace.save() }
    }
}
