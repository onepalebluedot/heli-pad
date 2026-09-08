import SwiftUI

public struct FamilyTemplatesView: View {
    public var templates: [TemplateItem]
    public var suggestions: [TemplateItem]
    public var onSelectTemplate: (TemplateItem) -> Void
    public var onAddTemplate: () -> Void
    public var onAdoptSuggestion: (TemplateItem) -> Void

    public init(
        templates: [TemplateItem],
        suggestions: [TemplateItem],
        onSelectTemplate: @escaping (TemplateItem) -> Void,
        onAddTemplate: @escaping () -> Void,
        onAdoptSuggestion: @escaping (TemplateItem) -> Void
    ) {
        self.templates = templates
        self.suggestions = suggestions
        self.onSelectTemplate = onSelectTemplate
        self.onAddTemplate = onAddTemplate
        self.onAdoptSuggestion = onAdoptSuggestion
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

            // AI Suggestions Card (if any)
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

                    Text("We noticed recurring activities in your schedule that can be saved as 1-tap shortcuts.")
                        .font(HeliTypography.caption(12))
                        .foregroundColor(HeliColors.mutedGray)

                    ForEach(suggestions) { sugg in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sugg.title)
                                    .font(HeliTypography.cardTitle(13))
                                    .foregroundColor(HeliColors.greenInk)
                                Text("\(sugg.location) · \(TimeFormat.formatDuration(sugg.duration))")
                                    .font(HeliTypography.caption(11))
                                    .foregroundColor(HeliColors.mutedGray)
                            }
                            Spacer()
                            Button(action: { onAdoptSuggestion(sugg) }) {
                                Text("+ Save")
                                    .font(HeliTypography.actionButton(11))
                                    .foregroundColor(HeliColors.forestGreen)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(HeliColors.cardWarmWhite)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(HeliColors.sageRule, lineWidth: 0.8))
                            }
                        }
                        .padding(10)
                        .background(HeliColors.cardWarmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(14)
                .background(HeliColors.butterLight.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(HeliColors.highlightGold.opacity(0.5), lineWidth: 1))
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
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(HeliColors.sageRule, lineWidth: 0.8))
        }
        .buttonStyle(PlainButtonStyle())
    }
}
