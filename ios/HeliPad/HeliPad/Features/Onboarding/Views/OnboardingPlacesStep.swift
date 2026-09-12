import SwiftUI

struct OnboardingPlacesStep: View {
    @Binding var draft: OnboardingDraft

    /// Starters, so the common places are one tap rather than three fields.
    private static let suggestions: [(label: String, icon: String)] = [
        ("School", "school"),
        ("Work", "building-2"),
        ("Sports field", "trophy"),
        ("Music", "music-2"),
        ("Clinic", "hospital"),
        ("Groceries", "shopping-cart")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeader(
                eyebrow: "Step 5 · Places · optional",
                title: "Where do you go most?",
                subtitle: "School, the field, the studio. The drive time you give is what the countdown works from until live routing is connected."
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Quick add")
                    .font(HeliTypography.railTitle(11.5))
                    .foregroundColor(HeliColors.mutedGray)
                OnboardingChipWrap(items: OnboardingPlacesStep.suggestions.map { $0.label }, perRow: 2) { label in
                    OnboardingChip(
                        label: label,
                        isSelected: false,
                        icon: OnboardingPlacesStep.icon(for: label),
                        action: { add(label) }
                    )
                }
            }

            ForEach($draft.places) { $place in
                OnboardingCardRow(onDelete: { remove(place.id) }) {
                    OnboardingField(label: "Place name", placeholder: "e.g. Oak Ridge Elementary", text: $place.name)
                    OnboardingField(label: "Address", placeholder: "2140 Schoolhouse Road", text: Binding(
                        get: { place.address },
                        set: { newAddress in
                            if place.address.caseInsensitiveCompare(newAddress) != .orderedSame {
                                place.latitude = nil
                                place.longitude = nil
                                place.placeId = nil
                                place.source = "manual"
                                place.routeKey = nil
                            }
                            place.address = newAddress
                        }
                    ))
                    Stepper(
                        "Drive from \(draft.homeName): \(place.minutesFromHome) min",
                        value: $place.minutesFromHome,
                        in: 1...120,
                        step: 1
                    )
                    .font(HeliTypography.body(13))
                    .foregroundColor(HeliColors.greenInk)
                }
            }

            OnboardingAddButton(label: "Add a place") {
                draft.places.append(OnboardingDraft.DraftPlace())
            }
        }
    }

    private static func icon(for label: String) -> String {
        return suggestions.first { $0.label == label }?.icon ?? "map-pin"
    }

    private func add(_ label: String) {
        draft.places.append(
            OnboardingDraft.DraftPlace(name: label, icon: OnboardingPlacesStep.icon(for: label))
        )
    }

    private func remove(_ id: String) {
        draft.places.removeAll { $0.id == id }
    }
}
