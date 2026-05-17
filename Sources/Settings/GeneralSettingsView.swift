import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showBackups = false
    @State private var backupList: [URL] = []

    var body: some View {
        @Bindable var state = appState
        Form {
            Section("外观") {
                Picker("画布背景", selection: $state.preferences.canvasBackground) {
                    Text("点阵网格").tag("dotGrid")
                    Text("纯色").tag("solid")
                    Text("透明").tag("transparent")
                }
                Toggle("Metal 渲染器（终端高性能模式）",
                       isOn: $state.preferences.metalRendererEnabled)
                    .help("使用 Metal GPU 加速终端渲染，可降低大量输出时的 CPU 占用")
            }

            Section("集成") {
                Picker("首选 IDE", selection: $state.preferences.preferredIDE) {
                    Text("Cursor").tag("cursor")
                    Text("VS Code").tag("vscode")
                    Text("Xcode").tag("xcode")
                }
                .help("在「View → Open in Editor」时使用的编辑器")

                Toggle("启用 Remote SSH", isOn: $state.preferences.sshEnabled)
                if appState.preferences.sshEnabled {
                    TextField("Host", text: $state.preferences.sshHost)
                        .textFieldStyle(.roundedBorder)
                    TextField("用户名", text: $state.preferences.sshUser)
                        .textFieldStyle(.roundedBorder)
                    LabeledContent("SSH Port") {
                        TextField("", value: $state.preferences.sshPort, format: .number)
                            .frame(width: 70)
                    }
                    LabeledContent("Tunnel Port") {
                        TextField("", value: $state.preferences.sshTunnelPort, format: .number)
                            .frame(width: 70)
                    }
                    .help("SSH 反向隧道端口（默认 7433），远端 omaestri CLI 通过此端口回连")
                    TextField("脚本路径", text: $state.preferences.sshScriptPath)
                        .textFieldStyle(.roundedBorder)
                        .help("omaestri 脚本安装路径（默认 ~/.local/bin/omaestri）")
                    Toggle("添加到 PATH", isOn: $state.preferences.sshAddToPath)
                    Button("连接") {
                        connectSSH()
                    }
                    .disabled(appState.preferences.sshHost.isEmpty || appState.preferences.sshUser.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("备份") {
                LabeledContent("自动备份") {
                    Text("每小时").foregroundStyle(.secondary)
                }
                Button("查看备份…") {
                    backupList = BackupManager.shared.listBackups()
                    showBackups = true
                }
            }

            Section("更新") {
                Button("检查更新…") {
                    (NSApp.delegate as? AppDelegate)?.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420)
        .onChange(of: appState.preferences) { _, _ in
            try? PersistenceManager.shared.savePreferences(appState.preferences)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openInEditor)) { _ in
            openInPreferredIDE()
        }
        .sheet(isPresented: $showBackups) {
            BackupListView(backups: backupList)
        }
    }

    private func connectSSH() {
        let prefs = appState.preferences
        let config = SSHConfig(
            host: prefs.sshHost,
            user: prefs.sshUser,
            port: prefs.sshPort,
            scriptPath: prefs.sshScriptPath,
            tunnelPort: prefs.sshTunnelPort,
            addToPath: prefs.sshAddToPath
        )
        Task.detached {
            try? SSHTunnelService.shared.startTunnel(config: config)
        }
    }

    private func openInPreferredIDE() {
        guard let ws = appState.workspaces.first(where: { $0.id == appState.activeWorkspaceId }) else { return }
        let dirURL = URL(fileURLWithPath: ws.workingDirectory)
        let bundleId: String
        switch appState.preferences.preferredIDE {
        case "cursor":  bundleId = "com.todesktop.230313mzl4w4u92"
        case "vscode":  bundleId = "com.microsoft.VSCode"
        case "xcode":   bundleId = "com.apple.dt.Xcode"
        default:
            NSWorkspace.shared.selectFile(ws.workingDirectory, inFileViewerRootedAtPath: ws.workingDirectory)
            return
        }
        NSWorkspace.shared.open(
            [dirURL],
            withAppBundleIdentifier: bundleId,
            options: [],
            additionalEventParamDescriptor: nil,
            launchIdentifiers: nil
        )
    }
}

// MARK: - 备份列表视图

struct BackupListView: View {
    let backups: [URL]
    @Environment(\.dismiss) private var dismiss
    @State private var restoreResult: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("备份列表")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding()

            Divider()

            if backups.isEmpty {
                Text("暂无备份")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(backups, id: \.path) { backup in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(backup.lastPathComponent)
                                .font(.body)
                            Text(backup.path)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("恢复") {
                            if let count = try? BackupManager.shared.restoreFromBackup(url: backup) {
                                restoreResult = "已确认 \(count) 个文件"
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            if let result = restoreResult {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(result)
                        .font(.caption)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 500, height: 320)
    }
}
