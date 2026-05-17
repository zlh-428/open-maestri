import SwiftUI
import OSLog

/// Landing（合并到目标分支）确认界面
struct LandingView: View {
    let floor: Floor
    let workingDirectory: String
    @State private var targetBranch = "main"
    @State private var diffText = ""
    @State private var isLanding = false
    @State private var landError: String?
    @State private var landSuccess = false
    var onLanded: (() -> Void)?
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "airplane")
                Text("Landing: \(floor.name)").font(.headline)
            }

            HStack {
                Text("目标分支：").foregroundStyle(.secondary)
                TextField("目标分支", text: $targetBranch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }

            if !diffText.isEmpty {
                ScrollView {
                    Text(diffText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 180)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let err = landError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }

            if landSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("合并成功！Floor 已完成。").foregroundStyle(.green)
                }
            }

            HStack {
                Button("取消", action: onCancel).keyboardShortcut(.escape)
                Spacer()
                Button("合并") { performLand() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(isLanding || landSuccess)
                if isLanding { ProgressView().scaleEffect(0.7) }
            }
        }
        .padding()
        .frame(width: 520)
        .onAppear { loadDiff() }
    }

    private func loadDiff() {
        Task.detached(priority: .userInitiated) {
            let result = (try? runGit(["diff", "--stat", floor.branchName], in: workingDirectory)) ?? ""
            await MainActor.run { diffText = result.isEmpty ? "(无差异)" : result }
        }
    }

    private func performLand() {
        isLanding = true
        landError = nil
        Task.detached(priority: .userInitiated) {
            do {
                try FloorManager.shared.land(floor: floor, targetBranch: targetBranch, workingDirectory: workingDirectory)
                await MainActor.run {
                    isLanding = false
                    landSuccess = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        onLanded?()
                    }
                }
            } catch {
                await MainActor.run {
                    isLanding = false
                    landError = error.localizedDescription
                }
            }
        }
    }

    @discardableResult
    private func runGit(_ args: [String], in directory: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
