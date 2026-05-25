import AppKit
import SwiftUI

// MARK: - Node Creation

extension WorkspaceCanvasView {

    func createNoteAtFrame(_ frame: CGRect) {
        let name = nextNodeName(for: "stickyNote")
        let fileName = "\(name).md"
        var nc = StickyNoteContent(name: name)
        nc.fileName = fileName
        let node = CanvasNode(
            frame: frame,
            content: .stickyNote(nc)
        )
        let filePath = PersistenceManager.shared.notesDirURL(workspaceId: workspace.id)
            .appendingPathComponent(fileName).path
        try? FileManager.default.createDirectory(
            atPath: PersistenceManager.shared.notesDirURL(workspaceId: workspace.id).path,
            withIntermediateDirectories: true
        )
        try? "".write(toFile: filePath, atomically: true, encoding: .utf8)
        NoteRegistry.shared.register(name: name, filePath: filePath, nodeId: node.id)
        workspace.addNode(node)
        Task { try? await workspace.save() }
    }

    func createFileTreeAtFrame(_ frame: CGRect) {
        let path = workspace.workingDirectory
        let fc = FileTreeContent(name: URL(fileURLWithPath: path).lastPathComponent, rootPath: path)
        let node = CanvasNode(
            frame: frame,
            content: .fileTree(fc)
        )
        workspace.addNode(node)
        Task { try? await workspace.save() }
    }

    func createTextAtFrame(_ frame: CGRect) {
        let tc = TextContent(text: "")
        let node = CanvasNode(
            frame: frame,
            content: .text(tc)
        )
        workspace.addNode(node)
        Task { try? await workspace.save() }
        NotificationCenter.default.post(
            name: .textNodeShouldBeginEditing,
            object: nil,
            userInfo: ["nodeId": node.id]
        )
    }

    func createShapeAtFrame(_ frame: CGRect) {
        let sc = ShapeContent()
        let node = CanvasNode(
            frame: frame,
            content: .shape(sc)
        )
        workspace.addNode(node)
        Task { try? await workspace.save() }
    }

    func createTerminalAtFrame(_ frame: CGRect, preset: AgentPreset, role: RolePreset?, isManager: Bool, workingDirectory: String? = nil) {
        let dir = workingDirectory ?? workspace.workingDirectory
        var tc = TerminalContent(
            name: preset.name,
            agentType: preset.agentType,
            command: preset.command,
            workingDirectory: dir
        )
        tc.isManager = isManager
        let node = CanvasNode(
            id: tc.id,
            frame: frame,
            content: .terminal(tc)
        )
        workspace.addNode(node)
        let wsId = workspace.id
        Task { @MainActor in
            _ = TerminalManager.shared.createTerminal(
                id: tc.id,
                command: preset.command,
                workingDirectory: tc.workingDirectory,
                workspaceId: wsId,
                roleName: role?.name,
                displayName: tc.name
            )
        }
        Task { try? await workspace.save() }
    }

    func createPortalAtFrame(_ frame: CGRect, name: String, url: String) {
        let portalName = name.isEmpty ? nextNodeName(for: "portal") : name
        let pc = PortalContent(name: portalName, url: url)
        let node = CanvasNode(
            frame: frame,
            content: .portal(pc)
        )
        workspace.addNode(node)
        Task { try? await workspace.save() }
    }

    /// 节点类型对应的默认尺寸
    func defaultNodeSize(for nodeType: String) -> CGSize {
        switch nodeType {
        case "terminal": return CGSize(width: 600, height: 400)
        case "stickyNote": return CGSize(width: 300, height: 240)
        case "portal": return CGSize(width: 500, height: 380)
        case "fileTree": return CGSize(width: 360, height: 480)
        case "text": return CGSize(width: 60, height: 28)
        case "linkedFile": return CGSize(width: 300, height: 240)
        default: return CGSize(width: 400, height: 300)
        }
    }

    /// 根据现有同类型节点数量生成递增编号名称
    func nextNodeName(for nodeType: String) -> String {
        let prefix: String
        switch nodeType {
        case "portal": prefix = "Portal"
        case "stickyNote": prefix = "Note"
        case "fileTree": prefix = "File Tree"
        case "text": prefix = "Text"
        case "shape": prefix = "Shape"
        default: prefix = "Node"
        }

        let existingCount = workspace.nodes.count { node in
            switch (nodeType, node.content) {
            case ("portal", .portal): return true
            case ("stickyNote", .stickyNote): return true
            case ("fileTree", .fileTree): return true
            case ("text", .text): return true
            case ("shape", .shape): return true
            default: return false
            }
        }

        return "\(prefix) #\(existingCount + 1)"
    }
}
