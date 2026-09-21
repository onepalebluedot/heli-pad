import SwiftUI
import AssistantKit

public struct FamilyTemplatesView: View {
    public var templates: [TemplateItem]
    public var suggestions: [ShortcutSuggestion]
    public var onSelectTemplate: (TemplateItem) -> Void
    public var onAddTemplate: () -> Void
    public var onReviewSuggestion: (ShortcutSuggestion) -> Void
    public var onDismissSuggestion: (ShortcutSuggestion) -> Void

    public init(
        templates: [TemplateItem],
        suggestions: [ShortcutSuggestion],
        onSelectTemplate: @escaping (TemplateItem) -> Void,
        onAddTemplate: @escaping () -> Void,
        onReviewSuggestion: @escaping (ShortcutSuggestion) -> Void,
        onDismissSuggestion: @escaping (ShortcutSuggestion) -> Void
    ) {
        self.templates = templates
        self.suggestions = suggestions
        self.onSelectTemplate = onSelectTemplate
        self.onAddTemplate = onAddTemplate
        self.onReviewSuggestion = onReviewSuggestion
        self.onDismissSuggestion = onDismissSuggestion
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                Text("ACTIVITY SHORTCUTS")
                    .font(HeliTypography.eyebrow(11))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.4)

                Spacer()

                Button(action: onAddTemplate) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("New Shortcut")
                            .font(HeliTypography.actionButton(11))
                    }
                    .foregroundColor(HeliColors.forestGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(HeliColors.forestTint)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)

            // Shown only when the assistant actually found something worth
            // offering. An empty list is a normal answer, and this section
            // disappearing is the correct outcome - the old version padded
            // itself with near-duplicates of shortcuts that already existed.
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundColor(HeliColors.highlightGold)
                        Text("SMART SUGGESTIONS")
                            .font(HeliTypography.eyebrow(10))
                            .foregroundColor(HeliColors.greenInk)
                            .tracking(1.2)
                    }

                    Text("Activities you have been adding by hand that a shortcut would save time on.")
                        .font(HeliTypography.caption(12))
                        .foregroundColor(HeliColors.mutedGray)

                    ForEach(suggestions) { suggestion in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(suggestion.label)
                                        .font(HeliTypography.cardTitle(13))
                                        .foregroundColor(HeliColors.greenInk)
                                    Text("\(suggestion.candidate.location) \u{00B7} around \(SuggestionService.timeLabel(for: suggestion.candidate))")
                                        .font(HeliTypography.caption(11))
                                        .foregroundColor(HeliColors.mutedGray)
                                    // App-computed, never asserted by the
                                    // model. The old card gave no reason at
                                    // all, which is what made it feel
                                    // arbitrary.
                                    Text(suggestion.evidence)
                                        .font(HeliTypography.caption(10.5))
                                        .foregroundColor(HeliColors.mutedGray)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 4)
                                Button(action: { onDismissSuggestion(suggestion) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(HeliColors.mutedGray)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Dismiss suggestion")
                            }

                            // Review, not save. Opening the editor writes
                            // nothing; the shortcut exists only if the user
                            // confirms there.
                            Button(action: { onReviewSuggestion(suggestion) }) {
                                Text("Review Shortcut")
                                    .font(HeliTypography.actionButton(12))
                                    .foregroundColor(HeliColors.forestGreen)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(HeliColors.cardWarmWhite)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(HeliColors.sageRule, lineWidth: 0.8))
                            }
                        }
                        .padding(10)
                        .background(HeliColors.cardWarmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(14)
                .background(HeliColors.butterLight.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(HeliColors.highlightGold.opacity(0.5), lineWidth: 1))
                .padding(.horizontal, 16)
            }

            // Grouped Templates
            let categories = TaskKind.categories
            ForEach(categories, id: \.self) { cat in
                let items = templates.filter {
                    if cat == "Other" {
                        return $0.category == nil || $0.category == "Other" || !categories.dropLast().contains($0.category ?? "")
                    }
                    return $0.category?.lowercased() == cat.lowercased()
                }

                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(HeliColors.categoryColor(cat))
                                .frame(width: 8, height: 8)
                            Text(cat.uppercased())
                                .font(HeliTypography.eyebrow(10))
                                .foregroundColor(HeliColors.mutedGray)
                                .tracking(1.2)
                            Text("(\(items.count))")
                                .font(HeliTypography.caption(10))
                                .foregroundColor(HeliColors.mutedGray)
                        }
                        .padding(.horizontal, 20)

                        VStack(spacing: 8) {
                            ForEach(items) { tmpl in
                                templateRow(tmpl: tmpl)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func templateRow(tmpl: TemplateItem) -> some View {
        Button(action: { onSelectTemplate(tmpl) }) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tmpl.title)
                        .font(HeliTypography.cardTitle(14))
                        .foregroundColor(HeliColors.greenInk)

                    HStack(spacing: 6) {
                        Text(tmpl.location)
                            .font(HeliTypography.caption(12))
                            .foregroundColor(HeliColors.mutedGray)

                        Text("•")
                            .foregroundColor(HeliColors.sageRule)

                        Text(TimeFormat.formatDuration(tmpl.duration))
                            .font(HeliTypography.caption(12))
                            .foregroundColor(HeliColors.mutedGray)

                        if !tmpl.kids.isEmpty {
                            Text("•")
                                .foregroundColor(HeliColors.sageRule)
                            ForEach(tmpl.kids, id: \.self) { kid in
                                Text(kid)
                                    .font(HeliTypography.chipLabel(10))
                                    .foregroundColor(HeliColors.greenInk)
                            }
                        }
                    }
                }

                Spacer()

                if tmpl.owner != "TBD" {
                    AvatarDisc(name: tmpl.owner, size: 22)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(HeliColors.mutedGray)
            }
            .padding(14)
            .background(HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(HeliColors.sageRule, lineWidth: 0.8))
        }
        .buttonStyle(PlainButtonStyle())
    }
}
