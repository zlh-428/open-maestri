import SwiftUI
import AppKit
import WebKit
import OSLog

private let dataSettingsLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "open-maestri", category: "DataSettings")

/// 数据管理设置页（对标 Maestri Settings → 数据）
/// 包含：存储位置、存储用量、自动保存、备份与恢复、全局存储、重置
struct DataSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var totalSize: Int64 = 0
    @State private var workspaceSizes: [(name: String, id: UUID, size: Int64)] = []
    @State private var lastBackupDate: Date?
    @State private var showDeleteConfirmation = false
    @State private var showClearStorageConfirmation = false
    @State private var deleteConfirmText = ""
    @State private var importResult: String?
    @State private var exportResult: String?

    private let pm = PersistenceManager.shared

    var body: some View {
        @Bindable var state = appState
        Form {
            storageLocationSection
            storageUsageSection
            autosaveSection
            backupSection
            globalStorageSection
            resetSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 420)
        .onAppear {
            refreshStorageInfo()
        }
        .onChange(of: appState.preferences) { _, _ in
            do {
                try PersistenceManager.shared.savePreferences(appState.preferences)
            } catch {
                dataSettingsLogger.error("Failed to save preferences: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 存储位置

    private var storageLocationSection: some View {
        Section("data.section.storage_location") {
            LabeledContent("data.location") {
                Text("~/" + Constants.appDataDirectoryName)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("data.button.reveal_in_finder") {
                    revealInFinder()
                }
            }
        }
    }

    // MARK: - 存储用量

    private var storageUsageSection: some View {
        Section("data.section.storage_usage") {
            LabeledContent("data.usage.total") {
                Text(formattedSize(totalSize))
                    .foregroundStyle(.secondary)
            }
            ForEach(workspaceSizes, id: \.id) { ws in
                LabeledContent(ws.name) {
                    Text(formattedSize(ws.size))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 自动保存

    private var autosaveSection: some View {
        @Bindable var state = appState
        return Section("data.section.autosave") {
            LabeledContent("data.autosave.interval") {
                HStack(spacing: 8) {
                    Button(action: decreaseInterval) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.preferences.autosaveIntervalSeconds <= 10)

                    Text("\(appState.preferences.autosaveIntervalSeconds)s")
                        .frame(width: 40)
                        .monospacedDigit()

                    Button(action: increaseInterval) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.preferences.autosaveIntervalSeconds >= 300)
                }
            }
            LabeledContent("data.autosave.last_save") {
                if let time = appState.lastAutosaveTime {
                    Text(time, style: .time)
                        .foregroundStyle(.secondary)
                } else {
                    Text("data.autosave.not_yet")
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - 备份与恢复

    private var backupSection: some View {
        Section("data.section.backup") {
            LabeledContent("data.backup.last_auto_backup") {
                if let date = lastBackupDate {
                    Text(relativeTimeString(from: date))
                        .foregroundStyle(.secondary)
                } else {
                    Text("data.backup.none")
                        .foregroundStyle(.tertiary)
                }
            }
            HStack {
                Spacer()
                Button("data.button.export_backup") {
                    exportBackup()
                }
                Button("data.button.import_backup") {
                    importBackup()
                }
            }
            if let result = importResult {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(result)
                        .font(.caption)
                }
            }
            if let result = exportResult {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(result)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - 全局存储

    private var globalStorageSection: some View {
        Section("data.section.global_storage") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("data.global_storage.shared_data") {
                    Text("data.global_storage.description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 240, alignment: .trailing)
                }
                HStack {
                    Spacer()
                    Button("data.button.clear_global_storage") {
                        showClearStorageConfirmation = true
                    }
                }
            }
        }
        .alert("data.alert.clear_storage.title", isPresented: $showClearStorageConfirmation) {
            Button("button.cancel", role: .cancel) {}
            Button("data.button.clear_global_storage", role: .destructive) {
                clearGlobalStorage()
            }
        } message: {
            Text("data.alert.clear_storage.message")
        }
    }

    // MARK: - 重置

    private var resetSection: some View {
        Section("data.section.reset") {
            HStack {
                Spacer()
                Button("data.button.delete_all_data", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .foregroundStyle(.red)
            }
        }
        .alert("data.alert.delete_all.title", isPresented: $showDeleteConfirmation) {
            TextField("data.alert.delete_all.placeholder", text: $deleteConfirmText)
            Button("button.cancel", role: .cancel) {
                deleteConfirmText = ""
            }
            Button("data.button.delete_all_data", role: .destructive) {
                if deleteConfirmText == "DELETE" {
                    deleteAllData()
                }
                deleteConfirmText = ""
            }
            .disabled(deleteConfirmText != "DELETE")
        } message: {
            Text("data.alert.delete_all.message")
        }
    }

    // MARK: - Actions

    private func revealInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: pm.appDataURL.path)
    }

    private func refreshStorageInfo() {
        Task.detached(priority: .background) {
            let sizes = BackupManager.shared.workspaceStorageSizes()
            let total = sizes.reduce(Int64(0)) { $0 + $1.size }
            let backup = BackupManager.shared.lastBackupDate()
            await MainActor.run {
                totalSize = total
                workspaceSizes = sizes
                lastBackupDate = backup
            }
        }
    }

    private func decreaseInterval() {
        let steps = [10, 30, 60, 120, 300]
        let current = appState.preferences.autosaveIntervalSeconds
        if let idx = steps.lastIndex(where: { $0 < current }) {
            appState.preferences.autosaveIntervalSeconds = steps[idx]
            appState.restartAutosave()
        }
    }

    private func increaseInterval() {
        let steps = [10, 30, 60, 120, 300]
        let current = appState.preferences.autosaveIntervalSeconds
        if let idx = steps.firstIndex(where: { $0 > current }) {
            appState.preferences.autosaveIntervalSeconds = steps[idx]
            appState.restartAutosave()
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = "open-maestri-backup.omaestribak"
        panel.title = "data.export.panel_title".localized
        panel.prompt = "data.export.panel_prompt".localized

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try BackupManager.shared.exportBackup(to: url)
            exportResult = "data.export.success".localized
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                exportResult = nil
            }
        } catch {
            dataSettingsLogger.error("Export failed: \(error)")
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.title = "data.import.panel_title".localized
        panel.prompt = "data.import.panel_prompt".localized

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try BackupManager.shared.importBackup(from: url)
            importResult = String(format: "data.import.success".localized, count)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                importResult = nil
            }
        } catch {
            dataSettingsLogger.error("Import failed: \(error)")
        }
    }

    private func clearGlobalStorage() {
        Task { @MainActor in
            await PortalWebViewStore.shared.clearGlobalStorage()
        }
    }

    private func deleteAllData() {
        do {
            try BackupManager.shared.deleteAllData()
            // 重启应用
            let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
            let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = [path]
            task.launch()
            NSApp.terminate(nil)
        } catch {
            dataSettingsLogger.error("Delete all data failed: \(error)")
        }
    }

    // MARK: - Formatting Helpers

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
