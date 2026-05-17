import AppKit
import SwiftUI

/// Git Diff 双列对比视图
struct DiffView: View {
    let diff: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diff.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(lineColor(line))
                            .frame(width: 4)
                        Text(line.isEmpty ? " " : line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(lineTextColor(line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    .background(lineBackground(line))
                }
            }
        }
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return .clear
    }

    private func lineTextColor(_ line: String) -> Color {
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return .secondary
    }

    private func lineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") { return Color.green.opacity(0.05) }
        if line.hasPrefix("-") { return Color.red.opacity(0.05) }
        return .clear
    }
}
