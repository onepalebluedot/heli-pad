import SwiftUI

public struct PlanTemplateStripView: View {
    public var templates: [TemplateItem]
    public var onSelectTemplate: (TemplateItem) -> Void

    public init(
        templates: [TemplateItem],
        onSelectTemplate: @escaping (TemplateItem) -> Void
    ) {
        self.templates = templates
        self.onSelectTemplate = onSelectTemplate
    }

    public var body: some View {
        if !templates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // Section Header
                HStack(spacing: 8) {
                    Text("SHORTCUTS")
                        .font(HeliTypography.eyebrow(11))
                        .foregroundColor(HeliColors.mutedGray)
                        .tracking(1.4)
                    Spacer()
                }
                .padding(.horizontal, 20)

                // Horizontal Carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(templates) { t in
                            templateCard(t: t)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func templateCard(t: TemplateItem) -> some View {
        Button(action: { onSelectTemplate(t) }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(t.category ?? "Activity")
                        .font(HeliTypography.eyebrow(9))
                        .foregroundColor(HeliColors.categoryColor(t.category ?? ""))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(HeliColors.categoryColor(t.category ?? "").opacity(0.12))
                        .clipShape(Capsule())

                    Spacer()

                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(HeliColors.forestGreen)
                }

                Text(t.title)
                    .font(HeliTypography.cardTitle(13))
                    .foregroundColor(HeliColors.greenInk)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(t.location)
                        .font(HeliTypography.caption(11))
                        .foregroundColor(HeliColors.mutedGray)
                        .lineLimit(1)
                }

                Text("\(TimeFormat.formatTime(t.time)) · \(TimeFormat.formatDurationShort(t.duration))")
                    .font(HeliTypography.chipLabel(10))
                    .foregroundColor(HeliColors.mutedGray)
            }
            .frame(width: 140)
            .padding(10)
            .background(HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(HeliColors.sageRule, lineWidth: 0.8)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
