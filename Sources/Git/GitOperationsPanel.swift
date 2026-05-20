import SwiftUI

/// Git 操作面板（Commit/Pull/Push 等）
struct GitOperationsPanel: View {
    let gitProvider: GitStatusProvider
    @State private var commitMessage = ""
    @State private var currentBranch = ""
    @State private var showDiff = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 分支名
            HStack {
                Image(systemName: "arrow.triangle.branch")
                Text(currentBranch.isEmpty ? "git.branch.unknown".localized : currentBranch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)

            Divider()

            // Commit
            TextField("git.commit_message_placeholder", text: $commitMessage)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)

            HStack(spacing: 4) {
                Button("button.commit") {
                    try? gitProvider.commit(message: commitMessage, files: [])
                    commitMessage = ""
                }
                .disabled(commitMessage.isEmpty)
                Button("Pull") { try? gitProvider.pull() }
                Button("Push") { try? gitProvider.push() }
                Button("Diff") { showDiff.toggle() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 8)
        }
        .onAppear {
            currentBranch = (try? gitProvider.currentBranch()) ?? ""
        }
    }
}
