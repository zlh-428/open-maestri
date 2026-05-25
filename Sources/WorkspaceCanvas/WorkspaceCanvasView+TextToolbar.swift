import SwiftUI
import AppKit

// MARK: - Text Toolbar Helpers

extension WorkspaceCanvasView {

    func textFontSize(nodeId: UUID) -> CGFloat {
        guard let node = workspace.nodes.first(where: { $0.id == nodeId }),
              case .text(let tc) = node.content else { return 16 }
        return tc.fontSize
    }

    func textFontWeight(nodeId: UUID) -> String {
        guard let node = workspace.nodes.first(where: { $0.id == nodeId }),
              case .text(let tc) = node.content else { return "regular" }
        return tc.fontWeight
    }

    func textFontFamily(nodeId: UUID) -> String {
        guard let node = workspace.nodes.first(where: { $0.id == nodeId }),
              case .text(let tc) = node.content else { return "sans" }
        return tc.fontFamily
    }

    func textCurrentColor(nodeId: UUID) -> String {
        guard let node = workspace.nodes.first(where: { $0.id == nodeId }),
              case .text(let tc) = node.content else { return "#000000" }
        return tc.color
    }

    func setTextFontSize(nodeId: UUID, size: CGFloat) {
        guard let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .text(var tc) = workspace.nodes[idx].content else { return }
        tc.fontSize = size
        workspace.nodes[idx].content = .text(tc)
        let newHeight = size + 16
        workspace.updateNodeFrame(id: nodeId, frame: CGRect(
            origin: workspace.nodes[idx].frame.origin,
            size: CGSize(width: workspace.nodes[idx].frame.width, height: newHeight)
        ))
        notifyTextContentChanged(nodeId: nodeId)
        Task { try? await workspace.save() }
    }

    func setTextFontWeight(nodeId: UUID, weight: String) {
        guard let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .text(var tc) = workspace.nodes[idx].content else { return }
        tc.fontWeight = weight
        workspace.nodes[idx].content = .text(tc)
        notifyTextContentChanged(nodeId: nodeId)
        Task { try? await workspace.save() }
    }

    func setTextFontFamily(nodeId: UUID, family: String) {
        guard let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .text(var tc) = workspace.nodes[idx].content else { return }
        tc.fontFamily = family
        workspace.nodes[idx].content = .text(tc)
        notifyTextContentChanged(nodeId: nodeId)
        Task { try? await workspace.save() }
    }

    func setTextColor(nodeId: UUID, color: String) {
        guard let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .text(var tc) = workspace.nodes[idx].content else { return }
        tc.color = color
        workspace.nodes[idx].content = .text(tc)
        notifyTextContentChanged(nodeId: nodeId)
        Task { try? await workspace.save() }
    }

    func notifyTextContentChanged(nodeId: UUID) {
        guard let node = workspace.nodes.first(where: { $0.id == nodeId }) else { return }
        NotificationCenter.default.post(
            name: .canvasNodeContentChanged,
            object: nil,
            userInfo: ["nodeId": nodeId, "content": node.content]
        )
    }
}
