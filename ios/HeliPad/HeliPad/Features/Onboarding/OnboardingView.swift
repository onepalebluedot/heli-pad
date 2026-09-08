import SwiftUI

// MARK: - Setup flow
//
// Seven questions, then the household is real. Answers live in a draft until
// the last screen, so backing out of setup leaves the current family alone.

public enum OnboardingStep: Int, CaseIterable {
    case welcome, you, home, crew, kids, places, activities, review

    var isSkippable: Bool {
        return self == .places || self == .activities
    }
}

public struct OnboardingView: View {
    @ObservedObject var store: AppStore
    @State private var draft: OnboardingDraft
    @State private var step: OnboardingStep = .welcome
    private let isRerun: Bool

    public init(store: AppStore) {
        self.store = store
        self.isRerun = store.hasCompletedOnboarding
        _draft = State(initialValue: store.onboardingStartingPoint())
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                stepContent
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
            }
            footer
        }
        .background(HeliColors.canvasIvory.ignoresSafeArea())
    }

    // MARK: - Chrome

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("VINCENT - PAD")
                    .font(HeliTypography.eyebrow(11))
                    .foregroundColor(HeliColors.forestGreen)
                    .tracking(2.0)
                Spacer()
                if isRerun {
                    Button("Cancel") { store.showOnboarding = false }
                        .font(HeliTypography.actionButton(13))
                        .foregroundColor(HeliColors.mutedGray)
                }
            }
            OnboardingProgressRule(step: step.rawValue, total: OnboardingStep.allCases.count)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeStep(isRerun: isRerun)
        case .you:
            OnboardingYouStep(draft: $draft)
        case .home:
            OnboardingHomeStep(draft: $draft)
        case .crew:
            OnboardingCrewStep(draft: $draft)
        case .kids:
            OnboardingKidsStep(draft: $draft)
        case .places:
            OnboardingPlacesStep(draft: $draft)
        case .activities:
            OnboardingActivitiesStep(draft: $draft)
        case .review:
            OnboardingReviewStep(draft: draft)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button(action: back) {
                    HStack(spacing: 5) {
                        HeliIcon("chevron-left", size: 12)
                        Text("Back")
                    }
                    .font(HeliTypography.buttonLabel(14.5))
                    .foregroundColor(HeliColors.mutedGray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            if step.isSkippable && !canAdvance {
                Button("Skip") { advance() }
                    .font(HeliTypography.buttonLabel(14.5))
                    .foregroundColor(HeliColors.mutedGray)
                    .padding(.vertical, 13)
            }

            Button(action: primaryAction) {
                HStack(spacing: 7) {
                    Text(primaryLabel)
                    HeliIcon(step == .review ? "check" : "arrow-right", size: 13)
                }
                .font(HeliTypography.buttonLabel(15))
                .foregroundColor(HeliColors.cardWarmWhite)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(canAdvance ? HeliColors.forestGreen : HeliColors.mutedGray.opacity(0.45))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(
            HeliColors.cardWarmWhite
                .overlay(alignment: .top) {
                    Rectangle().fill(HeliColors.sageRule).frame(height: 0.8)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Flow

    private var primaryLabel: String {
        switch step {
        case .welcome: return isRerun ? "Start over" : "Start"
        case .review: return "Finish setup"
        default: return "Next"
        }
    }

    /// Only the questions the app cannot work without gate the button; places
    /// and routines are optional and get a Skip instead.
    private var canAdvance: Bool {
        switch step {
        case .you: return draft.youStepIsComplete
        case .home: return draft.homeStepIsComplete
        case .kids: return draft.kidsStepIsComplete
        default: return true
        }
    }

    private func primaryAction() {
        if step == .review {
            store.applyOnboarding(draft)
        } else {
            advance()
        }
    }

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    private func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = previous }
    }
}
