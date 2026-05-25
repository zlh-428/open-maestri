import SwiftUI

// MARK: - Shape Toolbar Helpers

extension WorkspaceCanvasView {

    func shapeContent(nodeId: UUID) -> ShapeContent? {
        guard let node = workspace.nodes.first(where: { $0.id == nodeId }),
              case .shape(let sc) = node.content else { return nil }
        return sc
    }

    func setShapeContent(nodeId: UUID, content: ShapeContent) {
        guard let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        let newContent = NodeContent.shape(content)
        workspace.nodes[idx].content = newContent
        NotificationCenter.default.post(
            name: .canvasNodeContentChanged,
            object: nil,
            userInfo: ["nodeId": nodeId, "content": newContent]
        )
        Task { try? await workspace.save() }
    }
}
