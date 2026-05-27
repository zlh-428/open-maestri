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

    func createShapeAtFrame(_ frame: CGRect, shapeType: ShapeType = .rect) {
        var sc = ShapeContent()
        sc.shapeType = shapeType
        if let color = UserDefaults.standard.string(forKey: "drawingDefaultColor") {
            sc.strokeColor = color
            sc.fillColor = color
        }
        if let width = UserDefaults.standard.object(forKey: "drawingDefaultStrokeWidth") as? Double {
            sc.strokeWidth = CGFloat(width)
        }
        if let styleRaw = UserDefaults.standard.string(forKey: "drawingDefaultStrokeStyle"),
           let style = ShapeStrokeStyle(rawValue: styleRaw) {
            sc.strokeStyle = style
        }
        if let fillRaw = UserDefaults.standard.string(forKey: "drawingDefaultFillStyle"),
           let fill = ShapeFillStyle(rawValue: fillRaw) {
            sc.fillStyle = fill
        }
        let node = CanvasNode(
            frame: frame,
            content: .shape(sc)
        )
        workspace.addNode(node)
        Task { try? await workspace.save() }
    }

    func createStrokeAtFrame(_ frame: CGRect, strokeType: StrokeType,
                              startCanvas: CGPoint, endCanvas: CGPoint) {
        var sc = StrokeContent(strokeType: strokeType)
        let w = frame.width
        let h = frame.height
        sc.startPoint = CGPoint(
            x: w > 0 ? (startCanvas.x - frame.minX) / w : 0,
            y: h > 0 ? (startCanvas.y - frame.minY) / h : 0.5
        )
        sc.endPoint = CGPoint(
            x: w > 0 ? (endCanvas.x - frame.minX) / w : 1,
            y: h > 0 ? (endCanvas.y - frame.minY) / h : 0.5
        )
        if strokeType == .arrow {
            sc.controlPoint = CGPoint(
                x: (sc.startPoint.x + sc.endPoint.x) / 2,
                y: (sc.startPoint.y + sc.endPoint.y) / 2
            )
        }
        if let color = UserDefaults.standard.string(forKey: "drawingDefaultColor") {
            sc.strokeColor = color
        }
        if let width = UserDefaults.standard.object(forKey: "drawingDefaultStrokeWidth") as? Double {
            sc.strokeWidth = CGFloat(width)
        }
        if let styleRaw = UserDefaults.standard.string(forKey: "drawingDefaultStrokeStyle"),
           let style = ShapeStrokeStyle(rawValue: styleRaw) {
            sc.strokeStyle = style
        }
        let node = CanvasNode(frame: frame, content: .stroke(sc))
        workspace.addNode(node)
        Task { try? await workspace.save() }
    }

    func createFreehandFromPoints(_ normalizedPoints: [CGPoint],
                                   boundingFrame: CGRect,
                                   freehandType: FreehandType) {
        var fc = FreehandContent(freehandType: freehandType)
        fc.points = normalizedPoints
        if let color = UserDefaults.standard.string(forKey: "drawingDefaultColor") {
            fc.strokeColor = color
        }
        if let width = UserDefaults.standard.object(forKey: "drawingDefaultStrokeWidth") as? Double {
            fc.strokeWidth = CGFloat(width)
        }
        let node = CanvasNode(frame: boundingFrame, content: .freehand(fc))
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
        if let role {
            tc.assignedRoleId = role.id
            tc.color = role.color
            tc.icon = role.icon
        }
        let node = CanvasNode(
            id: tc.id,
            frame: frame,
            content: .terminal(tc)
        )
        workspace.addNode(node)
        let wsId = workspace.id
        Task { @MainActor in
            // 有角色时写入 role 文件并在 role 子目录启动
            let startDir: String
            if let role {
                RoleInjector.shared.prepareRoleDirectory(roleId: role.id, rolePreset: role, workingDirectory: dir)
                startDir = RoleInjector.shared.roleDirPath(roleId: role.id, workingDirectory: dir)
            } else {
                startDir = dir
            }
            _ = TerminalManager.shared.createTerminal(
                id: tc.id,
                command: preset.command,
                workingDirectory: startDir,
                workspaceId: wsId,
                roleName: role?.name,
                displayName: tc.name,
                agentType: preset.agentType
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
        case "text": return CGSize(width: 45, height: 35)
        case "linkedFile": return CGSize(width: 300, height: 240)
        case "ellipse", "diamond": return CGSize(width: 200, height: 160)
        case "stroke_line", "stroke_arrow": return CGSize(width: 200, height: 60)
        case "freehand_pen", "freehand_highlighter": return CGSize(width: 200, height: 100)
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
