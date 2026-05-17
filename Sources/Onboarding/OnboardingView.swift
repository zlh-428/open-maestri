import SwiftUI

/// 分层 Onboarding 视图（UX-DR12，三步引导）
struct OnboardingView: View {
    @Binding var hasCompleted: Bool
    @State private var step = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            switch step {
            case 0:
                OnboardingStep(
                    icon: "terminal.fill",
                    title: "欢迎使用 open-maestri",
                    subtitle: "在画布上可视化管理你的 AI Agent 团队",
                    buttonLabel: "开始"
                ) { step = 1 }
            case 1:
                OnboardingStep(
                    icon: "cpu",
                    title: "创建 Agent 终端",
                    subtitle: "从顶部工具栏拖入终端节点，选择 Claude Code / Codex / Shell 等预设",
                    buttonLabel: "继续"
                ) { step = 2 }
            default:
                OnboardingStep(
                    icon: "link",
                    title: "连接 Agent",
                    subtitle: "连线两个终端，omaestri skill 会自动注入，Agent 可以互相通信",
                    buttonLabel: "开始使用"
                ) { hasCompleted = true }
            }
            Spacer()

            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 24)
        }
        .frame(width: 480, height: 360)
    }
}

struct OnboardingStep: View {
    let icon: String
    let title: String
    let subtitle: String
    let buttonLabel: String
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(.blue)
            Text(title).font(.title2).fontWeight(.semibold)
            Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
            Button(buttonLabel, action: onContinue).buttonStyle(.borderedProminent)
        }
    }
}
