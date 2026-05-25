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
        let newFrame = CGRect(origin: workspace.nodes[idx].frame.origin, size: measuredTextNodeSize(tc))
        workspace.updateNodeFrame(id: nodeId, frame: newFrame)
        notifyTextContentChanged(nodeId: nodeId, frame: newFrame)
        Task { try? await workspace.save() }
    }

    func setTextFontWeight(nodeId: UUID, weight: String) {
        guard let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .text(var tc) = workspace.nodes[idx].content else { return }
        tc.fontWeight = weight
        workspace.nodes[idx].content = .text(tc)
        let newFrame = CGRect(origin: workspace.nodes[idx].frame.origin, size: measuredTextNodeSize(tc))
        workspace.updateNodeFrame(id: nodeId, frame: newFrame)
        notifyTextContentChanged(nodeId: nodeId, frame: newFrame)
        Task { try? await workspace.save() }
    }

    func setTextFontFamily(nodeId: UUID, family: String) {
        guard let idx = workspace.nodes.firstIndex(where: { $0.id == nodeId }),
              case .text(var tc) = workspace.nodes[idx].content else { return }
        tc.fontFamily = family
        workspace.nodes[idx].content = .text(tc)
        let newFrame = CGRect(origin: workspace.nodes[idx].frame.origin, size: measuredTextNodeSize(tc))
        workspace.updateNodeFrame(id: nodeId, frame: newFrame)
        notifyTextContentChanged(nodeId: nodeId, frame: newFrame)
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

    func notifyTextContentChanged(nodeId: UUID, frame: CGRect? = nil) {
        guard let node = workspace.nodes.first(where: { $0.id == nodeId }) else { return }
        var userInfo: [String: Any] = ["nodeId": nodeId, "content": node.content]
        if let frame { userInfo["frame"] = frame }
        NotificationCenter.default.post(name: .canvasNodeContentChanged, object: nil, userInfo: userInfo)
    }

    /// 根据 TextContent 的字体+文字测量节点应有的尺寸（含 padding）。
    func measuredTextNodeSize(_ tc: TextContent) -> CGSize {
        let nsWeight: NSFont.Weight = {
            switch tc.fontWeight {
            case "bold":   return .bold
            case "medium": return .medium
            default:       return .regular
            }
        }()
        let font: NSFont
        switch tc.fontFamily {
        case "serif":
            let desc = (NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
                .withDesign(.serif) ?? NSFont.systemFont(ofSize: tc.fontSize).fontDescriptor)
                .addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: nsWeight]])
            font = NSFont(descriptor: desc, size: tc.fontSize) ?? NSFont.systemFont(ofSize: tc.fontSize)
        case "mono":
            let desc = (NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
                .withDesign(.monospaced) ?? NSFont.systemFont(ofSize: tc.fontSize).fontDescriptor)
                .addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: nsWeight]])
            font = NSFont(descriptor: desc, size: tc.fontSize) ?? NSFont.systemFont(ofSize: tc.fontSize)
        default:
            font = NSFont.systemFont(ofSize: tc.fontSize, weight: nsWeight)
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: 0.3]
        let textWidth = tc.text.isEmpty
            ? 60
            : (tc.text as NSString).size(withAttributes: attrs).width
        let width  = max(80, textWidth + 20)   // 左右各 8pt padding + 余量
        let height = tc.fontSize + 16           // 上下各 6pt padding + 余量
        return CGSize(width: width, height: height)
    }
}
