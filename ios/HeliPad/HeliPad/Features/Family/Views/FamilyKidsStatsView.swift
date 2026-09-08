import SwiftUI

public struct FamilyKidsStatsView: View {
    public var children: [Person]
    @Binding public var selectedKid: String
    public var stats: KidStatsData

    public init(
        children: [Person],
        selectedKid: Binding<String>,
        stats: KidStatsData
    ) {
        self.children = children
        self._selectedKid = selectedKid
        self.stats = stats
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                Text("KIDS LOGISTICS & STATS")
                    .font(HeliTypography.eyebrow(11))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.4)
                Spacer()
            }
            .padding(.horizontal, 20)

            // Child Selector Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(children) { child in
                        let isSelected = selectedKid == child.name
                        Button(action: { selectedKid = child.name }) {
                            HStack(spacing: 6) {
                                AvatarDisc(name: child.name, size: 20)
                                Text(child.name)
                                    .font(HeliTypography.chipLabel(12))
                                    .foregroundColor(isSelected ? HeliColors.forestGreen : HeliColors.greenInk)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSelected ? HeliColors.forestTint : HeliColors.cardWarmWhite)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isSelected ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: isSelected ? 1.5 : 0.8))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Summary 4-stat grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statBox(title: "SCHEDULED TIME", value: String(format: "%.1fh", stats.totalHours), subtitle: "this week")
                statBox(title: "JOURNEYS & STOPS", value: "\(stats.journeyCount)", subtitle: "handoffs")
                statBox(title: "BUSIEST DAY", value: stats.busiestDay, subtitle: "peak logistics")
                statBox(title: "TOP ACTIVITY", value: stats.topCategory, subtitle: "primary focus")
            }
            .padding(.horizontal, 16)

            // Activity Mix
            VStack(alignment: .leading, spacing: 10) {
                Text("ACTIVITY MIX")
                    .font(HeliTypography.eyebrow(10))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.2)

                if stats.journeyCount > 0 {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(orderedCategories, id: \.self) { cat in
                                let count = stats.categoryMix[cat] ?? 0
                                let fraction = CGFloat(count) / CGFloat(max(1, stats.journeyCount))
                                let width = max(4, fraction * (geo.size.width - CGFloat(stats.categoryMix.count - 1) * 2))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(HeliColors.categoryColor(cat))
                                    .frame(width: width, height: 10)
                            }
                        }
                    }
                    .frame(height: 10)

                    // Categories Legend
                    HStack(spacing: 10) {
                        ForEach(orderedCategories, id: \.self) { cat in
                            let count = stats.categoryMix[cat] ?? 0
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(HeliColors.categoryColor(cat))
                                    .frame(width: 6, height: 6)
                                Text("\(cat): \(count)")
                                    .font(HeliTypography.caption(10))
                                    .foregroundColor(HeliColors.mutedGray)
                            }
                        }
                    }
                } else {
                    Text("No activities logged for \(selectedKid) yet.")
                        .font(HeliTypography.caption(12))
                        .foregroundColor(HeliColors.mutedGray)
                }
            }
            .padding(16)
            .background(HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(HeliColors.sageRule, lineWidth: 0.8))
            .padding(.horizontal, 16)

            // Caregiver Driver Distribution for this kid
            VStack(alignment: .leading, spacing: 10) {
                Text("CAREGIVER SPLIT")
                    .font(HeliTypography.eyebrow(10))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.2)

                if stats.journeyCount > 0 {
                    VStack(spacing: 6) {
                        ForEach(Array(stats.driverSplit.keys.sorted()), id: \.self) { driver in
                            let rides = stats.driverSplit[driver] ?? 0
                            let pct = (rides * 100) / max(1, stats.journeyCount)
                            HStack {
                                AvatarDisc(name: driver, size: 20)
                                Text(driver == "TBD" ? "Unassigned" : driver)
                                    .font(HeliTypography.caption(12))
                                    .foregroundColor(HeliColors.greenInk)
                                Spacer()
                                Text("\(rides) stops (\(pct)%)")
                                    .font(HeliTypography.chipLabel(11))
                                    .foregroundColor(HeliColors.mutedGray)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(HeliColors.sageRule, lineWidth: 0.8))
            .padding(.horizontal, 16)
        }
    }

    /// Legend and bar segments follow the category vocabulary, not alphabetical
    /// order, so the mix reads the same way every time.
    private var orderedCategories: [String] {
        TaskKind.categories.filter { (stats.categoryMix[$0] ?? 0) > 0 }
    }

    private func statBox(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(HeliTypography.eyebrow(9))
                .foregroundColor(HeliColors.mutedGray)
                .tracking(1.1)
            Text(value)
                .font(HeliTypography.headline(16))
                .foregroundColor(HeliColors.greenInk)
                .lineLimit(1)
            Text(subtitle)
                .font(HeliTypography.caption(10))
                .foregroundColor(HeliColors.mutedGray)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(HeliColors.sageRule, lineWidth: 0.8))
    }
}
