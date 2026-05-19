import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showBackups = false
    @State private var backupList: [URL] = []

    var body: some View {
        @Bindable var state = appState
        Form {
            Section("general.section.language") {
                Picker("general.language", selection: $state.preferences.language) {
                    ForEach(LocalizationManager.supportedLanguages, id: \.id) { lang in
                        Text("\(lang.localName) (\(lang.name))").tag(lang.id)
                    }
                }
                .onChange(of: state.preferences.language) { _, newLang in
                    LocalizationManager.shared.sync(from: newLang)
                }
            }

            Section("general.section.appearance") {
                Picker("general.canvas_background", selection: $state.preferences.canvasBackground) {
                    Text("general.background.dot_grid").tag("dotGrid")
                    Text("general.background.solid").tag("solid")
                    Text("general.background.transparent").tag("transparent")
                }
                Toggle("general.metal_renderer",
                       isOn: $state.preferences.metalRendererEnabled)
                    .help(String(localized: "general.metal_renderer.help"))
                    .onChange(of: state.preferences.metalRendererEnabled) { _, enabled in
                        applyMetalToAll(enabled: enabled)
                    }
            }

            Section("general.section.integration") {
                Picker("general.preferred_ide", selection: $state.preferences.preferredIDE) {
                    Text("Cursor").tag("cursor")
                    Text("VS Code").tag("vscode")
                    Text("Xcode").tag("xcode")
                }
                .help(String(localized: "general.preferred_ide.help"))

                Toggle("general.ssh_enabled", isOn: $state.preferences.sshEnabled)
                if appState.preferences.sshEnabled {
                    TextField("Host", text: $state.preferences.sshHost)
                        .textFieldStyle(.roundedBorder)
                    TextField("general.ssh_username", text: $state.preferences.sshUser)
                        .textFieldStyle(.roundedBorder)
                    LabeledContent("SSH Port") {
                        TextField("", value: $state.preferences.sshPort, format: .number)
                            .frame(width: 70)
                    }
                    LabeledContent("Tunnel Port") {
                        TextField("", value: $state.preferences.sshTunnelPort, format: .number)
                            .frame(width: 70)
                    }
                    .help(String(localized: "general.ssh_tunnel.help"))
                    TextField("general.ssh_script_path", text: $state.preferences.sshScriptPath)
                        .textFieldStyle(.roundedBorder)
                        .help(String(localized: "general.ssh_script_path.help"))
                    Toggle("general.ssh_add_to_path", isOn: $state.preferences.sshAddToPath)
                    Button("button.connect") {
                        connectSSH()
                    }
                    .disabled(appState.preferences.sshHost.isEmpty || appState.preferences.sshUser.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("general.section.backup") {
                LabeledContent("general.auto_backup") {
                    Text("general.auto_backup.hourly").foregroundStyle(.secondary)
                }
                Button("button.view_backups") {
                    backupList = BackupManager.shared.listBackups()
                    showBackups = true
                }
            }

            Section("general.section.update") {
                Button("button.check_updates") {
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

    private func applyMetalToAll(enabled: Bool) {
        Task { @MainActor in
            for id in TerminalManager.shared.terminals.keys {
                if let provider = TerminalProviderRegistry.shared.provider(for: id) {
                    provider.applyMetalRenderer(enabled: enabled)
                }
            }
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
                Text("general.backup_list.title")
                    .font(.headline)
                Spacer()
                Button("button.close") { dismiss() }
            }
            .padding()

            Divider()

            if backups.isEmpty {
                Text("general.backup_list.empty")
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
                        Button("button.restore") {
                            if let count = try? BackupManager.shared.restoreFromBackup(url: backup) {
                                restoreResult = "\(String(localized: "general.backup_list.restored")) \(count)"
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
