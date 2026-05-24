import SwiftUI

/// 工作区侧边栏：列表 + 右键菜单 + 快捷键切换
struct WorkspaceSidebarView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedId: UUID?
    @Binding var showCreate: Bool
    @State private var workspaceToDelete: WorkspaceEntry?
    @State private var workspaceToEdit: WorkspaceEntry?
    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false
    @State private var sidebarLayout = SidebarLayout()
    @State private var searchText = ""

    var body: some View {
        workspaceList
    }

    private var workspaceList: some View {
        workspaceListCore
        .navigationTitle("")
        .toolbar { addWorkspaceToolbarItem }
        .confirmationDialog(
            String(format: "workspace.delete_confirm".localized, workspaceToDelete?.name ?? ""),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            deleteConfirmButtons
        }
        .onChange(of: selectedId) { _, newId in
            appState.selectWorkspace(id: newId)
            if let id = newId {
                updateRecentWorkspaces(id: id)
            }
        }
        .onKeyPress(.upArrow, phases: .down) { _ in
            navigateWorkspace(direction: -1)
            return .handled
        }
        .onKeyPress(.downArrow, phases: .down) { _ in
            navigateWorkspace(direction: 1)
            return .handled
        }
        .sheet(isPresented: $showEditSheet) {
            if let entry = workspaceToEdit {
                EditWorkspaceSheet(entry: entry) { updated in
                    applyEdit(updated)
                }
                .environment(\.locale, LocalizationManager.shared.locale)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextWorkspace)) { _ in
            navigateWorkspace(direction: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .prevWorkspace)) { _ in
            navigateWorkspace(direction: -1)
        }
        .onAppear {
            sidebarLayout = (try? PersistenceManager.shared.loadSidebarLayout()) ?? SidebarLayout()
        }
        .onChange(of: appState.manifest.workspaces) { _, workspaces in
            // 保存工作区顺序
            sidebarLayout.topLevelItems = workspaces.map { $0.id }
            try? PersistenceManager.shared.saveSidebarLayout(sidebarLayout)
        }
        // 重命名分组 Alert
        .alert("workspace.rename_group.alert", isPresented: $showRenameGroup, presenting: groupToRename) { group in
            TextField("workspace.group_name", text: $renameGroupText)
            Button("button.confirm") {
                if let idx = sidebarLayout.groups.firstIndex(where: { $0.id == group.id }),
                   !renameGroupText.trimmingCharacters(in: .whitespaces).isEmpty {
                    sidebarLayout.groups[idx].name = renameGroupText.trimmingCharacters(in: .whitespaces)
                    saveSidebarLayout()
                }
            }
            Button("button.cancel", role: .cancel) {}
        } message: { _ in }
    }

    private var workspaceListCore: some View {
        let all: [WorkspaceEntry] = appState.manifest.workspaces
        let grouped: Set<UUID> = Set(sidebarLayout.groups.flatMap { $0.items })
        // 顶层条目：未加入任何分组的工作区
        let topLevel: [WorkspaceEntry]
        if searchText.isEmpty {
            topLevel = all.filter { !grouped.contains($0.id) }
        } else {
            topLevel = all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return List(selection: $selectedId) {
            // 分组（仅在非搜索状态下显示）
            if searchText.isEmpty {
                ForEach($sidebarLayout.groups) { $group in
                    let groupEntries = all.filter { group.items.contains($0.id) }
                    DisclosureGroup(isExpanded: Binding(
                        get: { !group.isCollapsed },
                        set: { group.isCollapsed = !$0; saveSidebarLayout() }
                    )) {
                        ForEach(groupEntries, id: \.id) { entry in
                            workspaceRowItem(entry: entry, inGroup: group.id)
                        }
                    } label: {
                        Label(group.name, systemImage: "folder")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contextMenu {
                                Button("button.rename_group") { renameGroup(group) }
                                Divider()
                                Button("button.delete_group", role: .destructive) { deleteGroup(group) }
                            }
                    }
                }
            }

            // 顶层工作区
            ForEach(topLevel, id: \.id) { entry in
                workspaceRowItem(entry: entry, inGroup: nil)
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "workspace.search".localized)
    }

    @ViewBuilder
    private func workspaceRowItem(entry: WorkspaceEntry, inGroup groupId: UUID?) -> some View {
        let ws = appState.workspaces.first(where: { $0.id == entry.id })
        WorkspaceRowView(
            entry: entry,
            terminalCount: ws?.terminalCount ?? 0,
            unreadCount: ws?.unreadActivityCount ?? 0
        )
        .tag(entry.id)
        .contextMenu(menuItems: {
            buildContextMenu(for: entry, inGroup: groupId)
        })
    }

    @State private var showRenameGroup = false
    @State private var groupToRename: SidebarGroup?
    @State private var renameGroupText = ""

    private var addWorkspaceToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { showCreate = true } label: {
                    Label("workspace.new", systemImage: "plus.square")
                }
                Divider()
                Button { addNewGroup() } label: {
                    Label("workspace.new_group", systemImage: "folder.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
            }
            .help("workspace.new_or_group".localized)
        }
    }

    @ViewBuilder
    private func workspaceRow(_ entry: WorkspaceEntry) -> some View {
        let ws = appState.workspaces.first(where: { $0.id == entry.id })
        WorkspaceRowView(
            entry: entry,
            terminalCount: ws?.terminalCount ?? 0,
            unreadCount: ws?.unreadActivityCount ?? 0
        )
        .tag(entry.id)
        .contextMenu(menuItems: { buildContextMenu(for: entry, inGroup: nil) })
    }

    // MARK: - 确认删除按钮

    @ViewBuilder
    private var deleteConfirmButtons: some View {
        Button("button.delete", role: .destructive) {
            if let entry = workspaceToDelete { deleteWorkspace(entry) }
        }
        Button("button.cancel", role: .cancel) {}
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private func buildContextMenu(for entry: WorkspaceEntry, inGroup groupId: UUID?) -> some View {
        Button("button.edit") { workspaceToEdit = entry; showEditSheet = true }
        Button("button.duplicate") { duplicateWorkspace(entry) }
        Divider()
        let pinLabel: LocalizedStringKey = entry.isPinned ? "workspace.unpin" : "workspace.pin"
        Button(pinLabel) { togglePin(entry) }
        Divider()
        if let gId = groupId {
            Button("button.remove_from_group") { moveOut(entry: entry, fromGroup: gId) }
            Divider()
        } else if !sidebarLayout.groups.isEmpty {
            Menu("workspace.move_to_group") {
                ForEach(sidebarLayout.groups) { group in
                    Button(group.name) { moveIn(entry: entry, toGroup: group.id) }
                }
            }
            Divider()
        }
        Button("button.delete", role: .destructive) { workspaceToDelete = entry; showDeleteConfirm = true }
    }

    // MARK: - 操作

    private func navigateWorkspace(direction: Int) {
        let entries = appState.manifest.workspaces
        guard !entries.isEmpty else { return }
        if let current = selectedId,
           let idx = entries.firstIndex(where: { $0.id == current }) {
            let next = (idx + direction + entries.count) % entries.count
            selectedId = entries[next].id
        } else {
            selectedId = entries.first?.id
        }
    }

    private func togglePin(_ entry: WorkspaceEntry) {
        var manifest = appState.manifest
        if let idx = manifest.workspaces.firstIndex(where: { $0.id == entry.id }) {
            manifest.workspaces[idx].isPinned.toggle()
            manifest.workspaces.sort { $0.isPinned && !$1.isPinned }
        }
        appState.manifest = manifest
        try? PersistenceManager.shared.saveManifest(manifest)
    }

    private func duplicateWorkspace(_ entry: WorkspaceEntry) {
        var manifest = appState.manifest
        var copy = entry
        copy.id = UUID()
        copy.name = "\(entry.name) \("workspace.duplicate_suffix".localized)"
        copy.isPinned = false
        manifest.workspaces.append(copy)
        appState.manifest = manifest
        try? PersistenceManager.shared.saveManifest(manifest)
    }

    private func updateRecentWorkspaces(id: UUID) {
        Task.detached(priority: .background) {
            var state = (try? PersistenceManager.shared.loadAppState()) ?? AppStateData()
            state.recentWorkspaceIds.removeAll { $0 == id }
            state.recentWorkspaceIds.insert(id, at: 0)
            if state.recentWorkspaceIds.count > 5 {
                state.recentWorkspaceIds = Array(state.recentWorkspaceIds.prefix(5))
            }
            try? PersistenceManager.shared.saveAppState(state)
        }
    }

    private func applyEdit(_ updated: WorkspaceEntry) {
        var manifest = appState.manifest
        if let idx = manifest.workspaces.firstIndex(where: { $0.id == updated.id }) {
            manifest.workspaces[idx] = updated
        }
        appState.manifest = manifest
        try? PersistenceManager.shared.saveManifest(manifest)
    }

    private func deleteWorkspace(_ entry: WorkspaceEntry) {
        var manifest = appState.manifest
        manifest.workspaces.removeAll { $0.id == entry.id }
        appState.manifest = manifest
        appState.workspaces.removeAll { $0.id == entry.id }
        if selectedId == entry.id {
            selectedId = manifest.workspaces.first?.id
        }
        try? PersistenceManager.shared.saveManifest(manifest)
    }

    // MARK: - 分组管理

    private func addNewGroup() {
        let group = SidebarGroup(name: String(format: "workspace.new_group".localized, sidebarLayout.groups.count + 1))
        sidebarLayout.groups.append(group)
        saveSidebarLayout()
    }

    private func renameGroup(_ group: SidebarGroup) {
        groupToRename = group
        renameGroupText = group.name
        showRenameGroup = true
    }

    private func deleteGroup(_ group: SidebarGroup) {
        // 删除分组时将其成员移回顶层
        sidebarLayout.groups.removeAll { $0.id == group.id }
        saveSidebarLayout()
    }

    private func moveIn(entry: WorkspaceEntry, toGroup groupId: UUID) {
        // 先从其他分组移除
        for i in sidebarLayout.groups.indices {
            sidebarLayout.groups[i].items.removeAll { $0 == entry.id }
        }
        // 加入目标分组
        if let idx = sidebarLayout.groups.firstIndex(where: { $0.id == groupId }) {
            sidebarLayout.groups[idx].items.append(entry.id)
        }
        saveSidebarLayout()
    }

    private func moveOut(entry: WorkspaceEntry, fromGroup groupId: UUID) {
        if let idx = sidebarLayout.groups.firstIndex(where: { $0.id == groupId }) {
            sidebarLayout.groups[idx].items.removeAll { $0 == entry.id }
        }
        saveSidebarLayout()
    }

    private func saveSidebarLayout() {
        try? PersistenceManager.shared.saveSidebarLayout(sidebarLayout)
    }
}

// MARK: - 工作区行

struct WorkspaceRowView: View {
    let entry: WorkspaceEntry
    var terminalCount: Int = 0
    var unreadCount: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .lineLimit(1)
                Text(entry.workingDirectory)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 4) {
                // 未读红点（任务完成角标）
                if unreadCount > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 18, height: 18)
                        Text("\(min(unreadCount, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                // 终端计数徽章
                if terminalCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "terminal")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text("\(terminalCount)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                }
                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
