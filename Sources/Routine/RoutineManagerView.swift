import SwiftUI

/// Routine 管理器视图（File → Routines… 打开）
struct RoutineManagerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showCreate = false
    @State private var routines: [Routine] = []

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(verbatim: "Routines")
                    .font(.headline)
                Spacer()
                Button("button.done") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            if routines.isEmpty {
                emptyState
            } else {
                routineList
            }

            Divider()

            // 底部工具栏
            HStack {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                    Text("routine.new")
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding()
        }
        .frame(width: 560, height: 400)
        .onAppear { routines = RoutineScheduler.shared.routines }
        .sheet(isPresented: $showCreate) {
            RoutineEditView(routines: $routines, availableTerminals: terminalList)
                .environment(\.locale, LocalizationManager.shared.locale)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("routine.empty")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("routine.empty.hint")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var routineList: some View {
        List {
            ForEach(routines) { routine in
                RoutineRow(routine: routine) {
                    toggleRoutine(routine)
                } onDelete: {
                    deleteRoutine(routine)
                }
            }
        }
        .listStyle(.plain)
    }

    private func toggleRoutine(_ routine: Routine) {
        Task { @MainActor in
            if routine.isActive {
                RoutineScheduler.shared.pause(id: routine.id)
            } else {
                RoutineScheduler.shared.resume(id: routine.id)
            }
            routines = RoutineScheduler.shared.routines
        }
    }

    private func deleteRoutine(_ routine: Routine) {
        Task { @MainActor in
            try? RoutineScheduler.shared.removeRoutine(id: routine.id)
            routines = RoutineScheduler.shared.routines
        }
    }

    private var terminalList: [(id: UUID, name: String)] {
        TerminalManager.shared.terminals.values.map { session in
            let name = session.roleName.map { "\(session.command) (\($0))" } ?? session.command
            return (id: session.id, name: name.isEmpty ? "Shell" : name)
        }.sorted { $0.name < $1.name }
    }
}

// MARK: - 单行

struct RoutineRow: View {
    let routine: Routine
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 活跃脉冲指示器
            ActiveIndicator(isActive: routine.isActive)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .font(.body)
                Text(intervalDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Pause/Resume 按钮
            Button {
                onToggle()
            } label: {
                Image(systemName: routine.isActive ? "pause.fill" : "play.fill")
                    .foregroundStyle(routine.isActive ? .orange : .green)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var intervalDescription: String {
        let secs = routine.intervalSeconds
        if secs < 60 { return "\(Int(secs))s 间隔 · \(routine.prompts.count) 条提示" }
        let mins = Int(secs / 60)
        if mins < 60 { return "每 \(mins) 分钟 · \(routine.prompts.count) 条提示" }
        return "每 \(Int(mins / 60)) 小时 · \(routine.prompts.count) 条提示"
    }
}

// MARK: - 活跃脉冲动画（绿色圆点）

struct ActiveIndicator: View {
    let isActive: Bool
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(isActive ? Color.green : Color.gray.opacity(0.4))
            .scaleEffect(scale)
            .onAppear {
                if isActive {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        scale = 1.4
                    }
                }
            }
            .onChange(of: isActive) { _, active in
                if active {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        scale = 1.4
                    }
                } else {
                    withAnimation(.default) { scale = 1.0 }
                }
            }
    }
}
