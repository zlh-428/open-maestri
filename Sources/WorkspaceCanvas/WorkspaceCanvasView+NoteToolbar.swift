import AppKit
import SwiftUI

// MARK: - Note Toolbar Helpers

extension WorkspaceCanvasView {

    func noteIsPreviewing(nodeId: UUID) -> Bool {
        guard let node = workspace.nodes.first(where: { $0.id == nodeId }),
              case .stickyNote(let nc) = node.content else { return false }
        return nc.isPreviewing
    }

    func noteFontSize(nodeId: UUID) -> Int {
        guard let node = workspace.nodes.first(where: { $0.id == nodeId }),
              case .stickyNote(let nc) = node.content else { return 14 }
        return nc.fontSize
    }

    func noteCurrentColor(nodeId: UUID) -> String {
        guard let node = workspace.nodes.first(where: { $0.id == nodeId }),
              case .stickyNote(let nc) = node.content else { return "yellow" }
        return nc.color
    }

    func toggleNoteFormatted(nodeId: UUID) {
        guard let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .stickyNote(var nc) = workspace.nodes[idx].content else { return }
        nc.isPreviewing.toggle()
        workspace.nodes[idx].content = .stickyNote(nc)
        NotificationCenter.default.post(
            name: .noteFormattedToggled,
            object: nil,
            userInfo: ["nodeId": nodeId, "isPreviewing": nc.isPreviewing]
        )
        Task { try? await workspace.save() }
    }

    func setNoteColor(nodeId: UUID, color: String) {
        guard let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .stickyNote(var nc) = workspace.nodes[idx].content else { return }
        nc.color = color
        let newContent = NodeContent.stickyNote(nc)
        workspace.nodes[idx].content = newContent
        NotificationCenter.default.post(
            name: .canvasNodeContentChanged,
            object: nil,
            userInfo: ["nodeId": nodeId, "content": newContent]
        )
        Task { try? await workspace.save() }
    }

    func setNoteFontSize(nodeId: UUID, size: Int) {
        guard let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .stickyNote(var nc) = workspace.nodes[idx].content else { return }
        nc.fontSize = size
        workspace.nodes[idx].content = .stickyNote(nc)
        NoteTextViewRegistry.shared.setFontSize(nodeId: nodeId, size: size)
        Task { try? await workspace.save() }
    }

    func saveNoteAs(nodeId: UUID) {
        guard let node = workspace.nodes.first(where: { $0.id == nodeId }),
              case .stickyNote(let nc) = node.content else { return }
        let filePath: String
        switch nc.storageMode {
        case .managed:
            let dir = PersistenceManager.shared.notesDirURL(workspaceId: workspace.id)
            filePath = dir.appendingPathComponent(nc.fileName ?? "\(nodeId).md").path
        case .custom(let path):
            filePath = path
        }
        guard let content = try? NoteFileManager.shared.read(filePath: filePath) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = nc.fileName ?? "note.md"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
