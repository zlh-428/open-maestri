import SwiftUI

/// Routine 创建/编辑视图
struct RoutineEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var routines: [Routine]
    /// 可选目标终端列表（(id, displayName)）
    var availableTerminals: [(id: UUID, name: String)]

    @State private var name = ""
    @State private var prompt = ""
    @State private var intervalMinutes: Double = 5
    @State private var selectedTerminalId: UUID?

    init(routines: Binding<[Routine]>, availableTerminals: [(id: UUID, name: String)] = []) {
        _routines = routines
        self.availableTerminals = availableTerminals
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("routine.new").font(.headline)

            Form {
                TextField("routine.name_placeholder", text: $name)
                TextField("routine.prompt_placeholder", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
                LabeledContent("routine.interval_minutes") {
                    Slider(value: $intervalMinutes, in: 1...120, step: 1)
                    Text("\(Int(intervalMinutes)) min").frame(width: 52)
                }
                if !availableTerminals.isEmpty {
                    Picker("terminal.target", selection: $selectedTerminalId) {
                        Text("role.none_tag").tag(UUID?.none)
                        ForEach(availableTerminals, id: \.id) { terminal in
                            Text(terminal.name).tag(UUID?.some(terminal.id))
                        }
                    }
                } else {
                    LabeledContent("terminal.target") {
                        Text("terminal.no_active").foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("button.cancel") { dismiss() }
                Spacer()
                Button("button.create") {
                    let targetId = selectedTerminalId ?? availableTerminals.first?.id ?? UUID()
                    let r = Routine(
                        name: name,
                        prompt: prompt,
                        intervalSeconds: intervalMinutes * 60,
                        targetTerminalId: targetId
                    )
                    routines.append(r)
                    Task { @MainActor in
                        try? RoutineScheduler.shared.addRoutine(r)
                    }
                    dismiss()
                }
                .disabled(name.isEmpty || prompt.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear {
            selectedTerminalId = availableTerminals.first?.id
        }
    }
}
