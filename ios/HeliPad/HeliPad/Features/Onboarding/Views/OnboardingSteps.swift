import SwiftUI

// MARK: - Welcome

struct OnboardingWelcomeStep: View {
    var isRerun: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingHeader(
                eyebrow: isRerun ? "Setup · again" : "Welcome",
                title: isRerun ? "Let's go through setup again." : "Let's set up your family.",
                subtitle: isRerun
                    ? "Your answers from last time are already filled in. Change what you like — finishing replaces the current household."
                    : "A few questions about who is in the house, where you go, and what happens each week. It takes about two minutes."
            )

            VStack(spacing: 10) {
                OnboardingWelcomeBullet(
                    icon: "users-round",
                    title: "Who is driving",
                    detail: "You and anyone else who does the school run."
                )
                OnboardingWelcomeBullet(
                    icon: "house",
                    title: "Where you start",
                    detail: "Home, and the places you drive to most."
                )
                OnboardingWelcomeBullet(
                    icon: "clock",
                    title: "What repeats",
                    detail: "The practices and lessons that fill a normal week."
                )
            }
        }
    }
}

private struct OnboardingWelcomeBullet: View {
    var icon: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HeliIcon(icon, size: 15)
                .foregroundColor(HeliColors.forestGreen)
                .frame(width: 34, height: 34)
                .background(HeliColors.forestTint)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HeliTypography.railTitle(13.5))
                    .foregroundColor(HeliColors.greenInk)
                Text(detail)
                    .font(HeliTypography.body(12.5))
                    .foregroundColor(HeliColors.mutedGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HeliColors.sageRule, lineWidth: 0.9)
        )
    }
}

// MARK: - You

struct OnboardingYouStep: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeader(
                eyebrow: "Step 1 · You",
                title: "Who are you in this family?",
                subtitle: "Your name is what the crew sees on every handoff, and the app opens on your day."
            )

            OnboardingField(label: "Your name", placeholder: "e.g. Sarah", text: $draft.yourName)

            VStack(alignment: .leading, spacing: 8) {
                Text("Your role")
                    .font(HeliTypography.railTitle(11.5))
                    .foregroundColor(HeliColors.mutedGray)
                OnboardingChipWrap(items: OnboardingDraft.caregiverRelationships, perRow: 3) { role in
                    OnboardingChip(
                        label: role,
                        isSelected: draft.yourRelationship == role,
                        action: { draft.yourRelationship = role }
                    )
                }
            }

            if !draft.yourName.trimmingCharacters(in: .whitespaces).isEmpty && !draft.youStepIsComplete {
                OnboardingNotice(
                    text: "\"\(draft.yourName)\" is how the app labels a group. Pick a personal name instead."
                )
            }
        }
    }
}

struct OnboardingNotice: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            HeliIcon("alert", size: 13)
                .foregroundColor(HeliColors.warningText)
            Text(text)
                .font(HeliTypography.body(12.5))
                .foregroundColor(HeliColors.warningText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(HeliColors.clayWash)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Home

struct OnboardingHomeStep: View {
    @Binding var draft: OnboardingDraft
    @State private var predictions: [PlacePrediction] = []
    @State private var isSearching: Bool = false
    @State private var isSelecting: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeader(
                eyebrow: "Step 2 · Home",
                title: "Where does the day start?",
                subtitle: "Every leave-by time is measured from here unless someone is out already."
            )

            OnboardingField(label: "What you call it", placeholder: "Home", text: $draft.homePlaceName)

            VStack(alignment: .leading, spacing: 6) {
                Text("Address")
                    .font(HeliTypography.railTitle(11.5))
                    .foregroundColor(HeliColors.mutedGray)

                HStack {
                    TextField("18 Redwood Lane (e.g. 25622 Coach Ln)", text: $draft.homeAddress)
                        .font(HeliTypography.body(15))
                        .foregroundColor(HeliColors.greenInk)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onChange(of: draft.homeAddress) { _, val in
                            if isSelecting {
                                isSelecting = false
                                return
                            }
                            searchTask?.cancel()
                            let q = val.trimmingCharacters(in: .whitespaces)
                            guard q.count >= 2 else {
                                predictions = []
                                isSearching = false
                                return
                            }
                            isSearching = true
                            searchTask = Task {
                                try? await Task.sleep(nanoseconds: 180_000_000)
                                if Task.isCancelled { return }
                                let results = await GoogleMapsService.shared.autocompletePlaces(query: q, locationBias: nil)
                                if !Task.isCancelled {
                                    await MainActor.run {
                                        self.predictions = results
                                        self.isSearching = false
                                    }
                                }
                            }
                        }

                    if isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(HeliColors.sageRule, lineWidth: 0.9)
                )

                if !predictions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(predictions) { pred in
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                isSelecting = true
                                let addr = pred.secondaryText.isEmpty ? pred.primaryText : "\(pred.primaryText), \(pred.secondaryText)"
                                draft.homeAddress = addr
                                predictions = []
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(HeliColors.forestGreen)
                                        .font(.system(size: 15))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pred.primaryText)
                                            .font(HeliTypography.cardTitle(13))
                                            .foregroundColor(HeliColors.greenInk)
                                            .lineLimit(1)
                                        if !pred.secondaryText.isEmpty {
                                            Text(pred.secondaryText)
                                                .font(HeliTypography.caption(11))
                                                .foregroundColor(HeliColors.mutedGray)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                        .font(.system(size: 11))
                                        .foregroundColor(HeliColors.mutedGray)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(Color.white)
                            }
                            .buttonStyle(.plain)

                            if pred.id != predictions.last?.id {
                                Divider()
                            }
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(HeliColors.sageRule, lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
                    .padding(.top, 2)
                }
            }
        }
    }
}

// MARK: - Crew

struct OnboardingCrewStep: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeader(
                eyebrow: "Step 3 · Crew",
                title: "Who else can take a drive?",
                subtitle: "A second parent, a grandparent, a nanny. Anyone the app is allowed to assign. You can skip this and add them later."
            )

            OnboardingCrewSelfCard(name: draft.trimmedYourName, role: draft.yourRelationship)

            ForEach($draft.crew) { $member in
                OnboardingCardRow(onDelete: { remove(member.id) }) {
                    OnboardingField(label: "Name", placeholder: "e.g. Mark", text: $member.name)
                    OnboardingChipWrap(items: OnboardingDraft.caregiverRelationships, perRow: 3) { role in
                        OnboardingChip(
                            label: role,
                            isSelected: member.relationship == role,
                            action: { member.relationship = role }
                        )
                    }
                }
            }

            OnboardingAddButton(label: "Add a caregiver") {
                draft.crew.append(OnboardingDraft.DraftPerson(relationship: "Father"))
            }
        }
    }

    private func remove(_ id: String) {
        draft.crew.removeAll { $0.id == id }
    }
}

private struct OnboardingCrewSelfCard: View {
    var name: String
    var role: String

    var body: some View {
        HStack(spacing: 11) {
            AvatarDisc(
                name: name.isEmpty ? "?" : name,
                size: 34,
                colorHex: OnboardingDraft.caregiverInks.first
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "You" : name)
                    .font(HeliTypography.railTitle(14))
                    .foregroundColor(HeliColors.greenInk)
                Text("\(role) · you")
                    .font(HeliTypography.caption(11.5))
                    .foregroundColor(HeliColors.mutedGray)
            }
            Spacer()
        }
        .padding(13)
        .background(HeliColors.forestTint.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Kids

struct OnboardingKidsStep: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeader(
                eyebrow: "Step 4 · Children",
                title: "Who are you driving?",
                subtitle: "Each child gets their own thread through the week, so you can see one kid's day on its own."
            )

            ForEach($draft.kids) { $kid in
                OnboardingCardRow(onDelete: { remove(kid.id) }) {
                    HStack(spacing: 11) {
                        AvatarDisc(name: kid.name, size: 32, isKid: true)
                        OnboardingField(label: "Name", placeholder: "e.g. Maya", text: $kid.name)
                    }
                }
            }

            OnboardingAddButton(label: "Add a child") {
                draft.kids.append(OnboardingDraft.DraftPerson(relationship: "Child"))
            }

            if draft.kids.isEmpty {
                Text("Add at least one child to continue.")
                    .font(HeliTypography.caption(12))
                    .foregroundColor(HeliColors.mutedGray)
            }
        }
    }

    private func remove(_ id: String) {
        draft.kids.removeAll { $0.id == id }
    }
}
