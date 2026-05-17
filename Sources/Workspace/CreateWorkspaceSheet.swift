import SwiftUI

/// 创建工作区 Sheet（FR1：工作目录、名称、图标）
struct CreateWorkspaceSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var workingDirectory: String = ""
    @State private var selectedIcon: String = "folder"
    @State private var isPickingDirectory = false

    private let iconOptions = [
        "folder", "folder.fill", "terminal.fill", "cpu",
        "brain", "desktopcomputer", "network", "server.rack"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("新建工作区")
                    .font(.headline)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("创建") { createWorkspace() }
                    .keyboardShortcut(.return)
                    .disabled(name.isEmpty || workingDirectory.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            Form {
                Section("基本信息") {
                    TextField("工作区名称", text: $name)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        TextField("工作目录", text: $workingDirectory)
                            .textFieldStyle(.roundedBorder)
                        Button("选择…") { pickDirectory() }
                    }
                }

                Section("图标") {
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

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择工作区目录"
        if panel.runModal() == .OK, let url = panel.url {
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
        let pm = PersistenceManager.shared

        // 1. 创建目录和初始 workspace.json（同步，确保文件存在后再 dismiss）
        try? pm.ensureWorkspaceDirectoryExists(id: entry.id)
        let payload = WorkspacePayload(id: entry.id, name: name, workingDirectory: workingDirectory)
        let doc = WorkspaceDocument(payload: payload)
        try? pm.saveSync(doc, to: pm.workspaceURL(id: entry.id))

        // 2. 更新 manifest（同步持久化）
        var manifest = appState.manifest
        manifest.workspaces.append(entry)
        appState.manifest = manifest
        try? pm.saveManifest(manifest)

        // 3. 立即创建 WorkspaceManager 实例并加入 AppState.workspaces
        //    （这是关键：ContentView 的 detail 通过 appState.workspaces 查找工作区）
        let ws = WorkspaceManager(entry: entry)
        try? ws.load()
        appState.workspaces.append(ws)

        // 4. 激活新工作区
        appState.activeWorkspaceId = entry.id

        // 5. Spotlight 更新
        SpotlightIndexer.shared.indexWorkspace(
            id: entry.id,
            name: entry.name,
            workingDirectory: entry.workingDirectory
        )

        dismiss()
    }
}
