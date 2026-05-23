import SwiftUI

struct NoteNodeSwiftUIView: View {
    let nodeId: UUID
    let content: StickyNoteContent
    let isSelected: Bool
    let isLocked: Bool
    let zoom: CGFloat
    let workspace: WorkspaceManager?
    var onActivated: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onDuplicate: ((UUID) -> Void)?
    var onLockToggle: ((UUID, Bool) -> Void)?

    var body: some View {
        NodeShellView(
            nodeId: nodeId,
            title: content.fileName ?? "Note",
            isSelected: isSelected,
            isLocked: isLocked,
            zoom: zoom,
            headerIcon: "note.text",
            headerColor: noteColor(content.color),
            themeColor: noteColor(content.color),
            onClose: { onClose?(nodeId) },
            onRename: { onRename?(nodeId, $0) },
            onDuplicate: { onDuplicate?(nodeId) },
            onLockToggle: { onLockToggle?(nodeId, $0) }
        ) {
            if let workspace {
                NoteEditorRepresentable(nodeId: nodeId, content: content, workspace: workspace)
            } else {
                Color.clear
            }
        }
    }

    private func noteColor(_ str: String) -> Color {
        NoteColorPickerPopover.colorFromString(str)
    }
}

/// NSViewControllerRepresentable 包裹现有 NoteNodeViewController
struct NoteEditorRepresentable: NSViewControllerRepresentable {
    let nodeId: UUID
    let content: StickyNoteContent
    let workspace: WorkspaceManager

    func makeNSViewController(context: Context) -> NoteNodeViewController {
        let filePath = resolvedFilePath()
        return NoteNodeViewController(noteId: nodeId, filePath: filePath)
    }

    func updateNSViewController(_ nsViewController: NoteNodeViewController, context: Context) {}

    private func resolvedFilePath() -> String {
        switch content.storageMode {
        case .managed:
            let notesDir = PersistenceManager.shared.notesDirURL(workspaceId: workspace.id)
            return notesDir.appendingPathComponent(content.fileName ?? "\(nodeId).md").path
        case .custom(path: let customPath):
            return customPath
        }
    }
}
