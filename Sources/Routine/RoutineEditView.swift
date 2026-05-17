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
            Text("新建 Routine").font(.headline)

            Form {
                TextField("名称", text: $name)
                TextField("提示（用 && 分隔多条）", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
                LabeledContent("间隔（分钟）") {
                    Slider(value: $intervalMinutes, in: 1...120, step: 1)
                    Text("\(Int(intervalMinutes)) min").frame(width: 52)
                }
                if !availableTerminals.isEmpty {
                    Picker("目标终端", selection: $selectedTerminalId) {
                        Text("（无）").tag(UUID?.none)
                        ForEach(availableTerminals, id: \.id) { terminal in
                            Text(terminal.name).tag(UUID?.some(terminal.id))
                        }
                    }
                } else {
                    LabeledContent("目标终端") {
                        Text("暂无活跃终端").foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("创建") {
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
