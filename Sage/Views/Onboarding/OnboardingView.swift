import SwiftUI

/// Root container for the multi-step onboarding flow.
/// Hosts a progress bar and drives step transitions via OnboardingViewModel.
struct OnboardingView: View {

    var onComplete: (() -> Void)?

    @StateObject private var vm = OnboardingViewModel()

    var body: some View {
        ZStack {
            if vm.isComplete {
                OnboardingCompletionView(onComplete: onComplete)
                    .transition(.opacity)
            } else {
                formFlow
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.isComplete)
    }

    // MARK: - Form Flow

    private var formFlow: some View {
        VStack(spacing: 0) {
            header
            progressBar

            // Step content — scrollable so keyboard doesn't obscure input
            ScrollView {
                stepContent
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .padding(.bottom, 120) // space above bottom bar
            }
            .scrollDismissesKeyboard(.interactively)

            bottomBar
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if vm.currentStep.previous != nil {
                Button(action: { withAnimation { vm.goBack() } }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
            } else {
                Spacer().frame(width: 44)
            }

            Spacer()

            Text(vm.currentStep.title)
                .font(.headline)

            Spacer()

            // Balance the back button on the right
            Spacer().frame(width: 44)
        }
        .padding(.horizontal, 8)
        .padding(.top, 16)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemGray5))
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * vm.progress, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: vm.progress)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch vm.currentStep {
        case .skillInput:
            SkillInputView(vm: vm)
        case .levelSelection:
            LevelSelectionView(vm: vm)
        case .metricSelection:
            MetricSelectionView(vm: vm)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                Button(action: { withAnimation { vm.advance() } }) {
                    let isLast = vm.currentStep.next == nil
                    Text(isLast ? "Finish" : "Next")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            vm.isCurrentStepValid
                                ? Color.accentColor
                                : Color(.systemGray4)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!vm.isCurrentStepValid)
                .animation(.easeInOut(duration: 0.2), value: vm.isCurrentStepValid)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    OnboardingView()
}
