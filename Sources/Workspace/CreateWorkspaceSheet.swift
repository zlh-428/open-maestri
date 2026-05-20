import SwiftUI

/// 创建工作区 Sheet（FR1：工作目录、名称、图标）
struct CreateWorkspaceSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var selectedIcon: String = "folder"

    private let iconOptions = [
        "folder", "folder.fill", "terminal.fill", "cpu",
        "brain", "desktopcomputer", "network", "server.rack"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("workspace.new")
                    .font(.headline)
                Spacer()
                Button("button.cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("button.create") { createWorkspace() }
                    .keyboardShortcut(.return)
                    .disabled(name.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            Form {
                Section("workspace.section.basic_info") {
                    TextField("workspace.name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(abbreviatedPath(workingDirectory))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("button.choose_directory") { pickDirectory() }
                            .controlSize(.small)
                    }
                }

                Section("workspace.section.icon") {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 8), spacing: 8) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .frame(width: 32, height: 32)
                                    .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 480, height: 360)
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "panel.select_workspace_dir".localized
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            workingDirectory = url.path
            if name.isEmpty {
                name = url.lastPathComponent
            }
        }
    }

    private func createWorkspace() {
        let entry = WorkspaceEntry(
            name: name,
            workingDirectory: workingDirectory,
            icon: selectedIcon
        )
        // 在 dismiss 前快照 manifest 和 appState 强引用，避免 sheet 销毁后 @Environment 失效
        let currentManifest = appState.manifest
        let capturedAppState = appState

        dismiss()

        Task.detached(priority: .userInitiated) {
            let pm = PersistenceManager.shared

            // 1. 创建目录和初始 workspace.json
            try? pm.ensureWorkspaceDirectoryExists(id: entry.id)
            let payload = WorkspacePayload(id: entry.id, name: entry.name, workingDirectory: entry.workingDirectory)
            let doc = WorkspaceDocument(payload: payload)
            try? pm.saveSync(doc, to: pm.workspaceURL(id: entry.id))

            // 2. 持久化 manifest
            var newManifest = currentManifest
            newManifest.workspaces.append(entry)
            try? pm.saveManifest(newManifest)

            // 3. 构造 WorkspaceManager（不需要 load，刚创建的是空工作区）
            let ws = WorkspaceManager(entry: entry)

            // 4. 回主线程更新 UI 状态（用强引用 capturedAppState，不会因 sheet 销毁而为 nil）
            let finalManifest = newManifest
            await MainActor.run {
                capturedAppState.manifest = finalManifest
                capturedAppState.workspaces.append(ws)
                capturedAppState.selectWorkspace(id: entry.id)
                NotificationCenter.default.post(
                    name: .workspaceCreated,
                    object: nil,
                    userInfo: ["workspaceId": entry.id]
                )
            }

            // 5. Spotlight 更新
            SpotlightIndexer.shared.indexWorkspace(
                id: entry.id,
                name: entry.name,
                workingDirectory: entry.workingDirectory
            )
        }
    }
}
