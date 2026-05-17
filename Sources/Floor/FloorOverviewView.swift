import SwiftUI
import OSLog

/// Floor 总览视图（⌘⇧\ 打开，右下角按钮打开）
struct FloorOverviewView: View {
    @Bindable var workspace: WorkspaceManager
    @State private var selectedFloorId: UUID? = nil
    @State private var showCreateFloor = false
    @State private var showLanding = false
    @State private var landingFloor: Floor? = nil
    @State private var errorMessage: String? = nil
    @State private var hooksFloor: Floor? = nil
    @State private var showHooksSheet = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("工作分支（Floors）").font(.headline)
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 6) {
                    // Ground 层（始终存在）
                    FloorRowView(
                        name: "Ground",
                        branchName: currentBranch(),
                        isSelected: selectedFloorId == nil,
                        isGround: true
                    ) {
                        selectedFloorId = nil
                    } onHooks: {} onLand: {}

                    ForEach(floors) { floor in
                        FloorRowView(
                            name: floor.name,
                            branchName: floor.branchName,
                            isSelected: selectedFloorId == floor.id,
                            isGround: false
                        ) {
                            selectedFloorId = floor.id
                        } onHooks: {
                            hooksFloor = floor
                            showHooksSheet = true
                        } onLand: {
                            landingFloor = floor
                            showLanding = true
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            if let err = errorMessage {
                Text(err).foregroundStyle(.red).font(.caption).padding(.horizontal)
            }

            Divider()

            HStack {
                Button("+ 新建 Floor") { showCreateFloor = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(workspace.workingDirectory.isEmpty)
                Spacer()
            }
            .padding()
        }
        .frame(width: 340, height: 400)
        .sheet(isPresented: $showCreateFloor) {
            CreateFloorSheet(workingDirectory: workspace.workingDirectory) { name, branch in
                createFloor(name: name, branchName: branch)
            }
        }
        .sheet(isPresented: $showLanding) {
            if let floor = landingFloor {
                LandingView(floor: floor, workingDirectory: workspace.workingDirectory) {
                    // Landing 成功后删除 floor
                    removeFloor(floor)
                    showLanding = false
                } onCancel: {
                    showLanding = false
                }
            }
        }
        .sheet(isPresented: $showHooksSheet) {
            if let floor = hooksFloor,
               let entryIdx = workspace.floors.firstIndex(where: { $0.id == floor.id }) {
                HooksConfigSheet(hooks: Binding(
                    get: { workspace.floors[entryIdx].hooks },
                    set: { newHooks in
                        workspace.floors[entryIdx].hooks = newHooks
                        Task { try? await workspace.save() }
                    }
                ), floorName: floor.name)
            }
        }
    }

    private var floors: [Floor] {
        workspace.floors.compactMap { entry in
            // 用 entry.worktreePath 保证路径一致（不重新计算）
            var floor = Floor(id: entry.id, name: entry.name,
                              branchName: entry.branchName,
                              workspaceDir: workspace.workingDirectory)
            floor.worktreePath = entry.worktreePath
            floor.hooks = entry.hooks
            return floor
        }
    }

    private func currentBranch() -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
        proc.currentDirectoryURL = URL(fileURLWithPath: workspace.workingDirectory)
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run(); proc.waitUntilExit()
        return (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "main")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createFloor(name: String, branchName: String) {
        Task.detached(priority: .userInitiated) {
            do {
                let floor = try FloorManager.shared.createFloor(
                    name: name, branchName: branchName,
                    workingDirectory: workspace.workingDirectory
                )
                let entry = FloorEntry(
                    id: floor.id, name: floor.name,
                    branchName: floor.branchName,
                    worktreePath: floor.worktreePath,
                    hooks: floor.hooks,
                    createdAt: floor.createdAt
                )
                await MainActor.run {
                    workspace.floors.append(entry)
                    Task { try? await workspace.save() }
                }
                try await HooksManager.shared.runSetupHooks(floor: floor, workingDirectory: workspace.workingDirectory)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func removeFloor(_ floor: Floor) {
        // 先在主线程更新 UI 状态，再在后台执行文件系统操作
        let dir = workspace.workingDirectory
        workspace.floors.removeAll { $0.id == floor.id }
        Task { try? await workspace.save() }
        // 后台执行 hooks + worktree 移除（不需要 @MainActor）
        Task.detached(priority: .utility) {
            try? await HooksManager.shared.runTeardownHooks(floor: floor, workingDirectory: dir)
            try? FloorManager.shared.removeFloor(floor, workingDirectory: dir)
        }
    }
}

// MARK: - Floor 行

struct FloorRowView: View {
    let name: String
    let branchName: String
    let isSelected: Bool
    let isGround: Bool
    let onSelect: () -> Void
    let onHooks: () -> Void
    let onLand: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body)
                Text(branchName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !isGround {
                Button("Land") { onLand() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button {
                    onHooks()
                } label: {
                    Image(systemName: "bolt.fill")
                }
                .buttonStyle(.plain)
                .help("配置 Hooks")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Hooks 配置 Sheet

/// 编辑 Floor 的 Setup/Run/Teardown Hooks（shell 命令列表）
struct HooksConfigSheet: View {
    @Binding var hooks: FloorHooks
    let floorName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("Hooks — \(floorName)")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    HooksPhaseSection(
                        title: "Setup",
                        subtitle: "创建 Floor 后自动执行",
                        systemImage: "play.circle",
                        commands: $hooks.setup
                    )

                    Toggle("自动执行 Setup Hooks", isOn: $hooks.autoRunSetup)
                        .padding(.horizontal)

                    Divider()

                    HooksPhaseSection(
                        title: "Run",
                        subtitle: "手动触发时执行",
                        systemImage: "bolt.circle",
                        commands: $hooks.run
                    )

                    Divider()

                    HooksPhaseSection(
                        title: "Teardown",
                        subtitle: "Landing/删除 Floor 前执行",
                        systemImage: "stop.circle",
                        commands: $hooks.teardown
                    )
                }
                .padding(.vertical, 12)
            }
        }
        .frame(width: 480, height: 520)
    }
}

// MARK: - 单个阶段 Hooks 编辑区

struct HooksPhaseSection: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var commands: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    commands.append("")
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            if commands.isEmpty {
                Text("无命令")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
            } else {
                ForEach(commands.indices, id: \.self) { idx in
                    HStack(spacing: 6) {
                        TextField("shell 命令…", text: $commands[idx])
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                        Button {
                            commands.remove(at: idx)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

// MARK: - 创建 Floor Sheet

struct CreateFloorSheet: View {
    let workingDirectory: String
    let onCreate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var floorName = ""
    @State private var branchName = ""
    @State private var useExistingBranch = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("新建 Floor").font(.headline)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Button("创建") { onCreate(floorName, branchName); dismiss() }
                    .disabled(floorName.isEmpty || branchName.isEmpty)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }.padding()
            Divider()
            Form {
                TextField("Floor 名称", text: $floorName)
                    .onChange(of: floorName) { _, v in
                        if !useExistingBranch {
                            branchName = v.lowercased().replacingOccurrences(of: " ", with: "-")
                        }
                    }
                TextField("分支名", text: $branchName)
                Toggle("使用已有分支", isOn: $useExistingBranch)
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 360, height: 220)
    }
}
