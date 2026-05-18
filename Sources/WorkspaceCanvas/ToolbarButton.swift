import SwiftUI

// MARK: - 二级工具栏按钮（自定义 hover tooltip）

struct ContextToolbarButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false
    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isHovered ? Color(white: 0.15) : Color(white: 0.35))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovered ? Color.black.opacity(0.05) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            HoverTrackingView { hovering in
                if hovering {
                    if !isHovered {
                        isHovered = true
                        hoverTask = Task {
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            guard !Task.isCancelled else { return }
                            showTooltip = true
                        }
                    }
                } else {
                    isHovered = false
                    hoverTask?.cancel()
                    hoverTask = nil
                    showTooltip = false
                }
            }
        )
        .overlay(alignment: .bottom) {
            if showTooltip && !tooltip.isEmpty {
                Text(tooltip)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(white: 0.88), lineWidth: 0.5)
                    )
                    .fixedSize()
                    .offset(y: 34)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                    .zIndex(1000)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showTooltip)
    }
}
