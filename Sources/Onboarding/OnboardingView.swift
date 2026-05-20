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
                    title: "onboarding.step1.title".localized,
                    subtitle: "onboarding.step1.subtitle".localized,
                    buttonLabel: "button.start".localized
                ) { step = 1 }
            case 1:
                OnboardingStep(
                    icon: "cpu",
                    title: "onboarding.step2.title".localized,
                    subtitle: "onboarding.step2.subtitle".localized,
                    buttonLabel: "button.continue".localized
                ) { step = 2 }
            default:
                OnboardingStep(
                    icon: "link",
                    title: "onboarding.step3.title".localized,
                    subtitle: "onboarding.step3.subtitle".localized,
                    buttonLabel: "button.get_started".localized
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
