import SwiftUI

public struct FamilyWorkloadCardView: View {
    public var loads: [(name: String, minutes: Int, color: Color)]
    public var totalMinutes: Int

    public init(loads: [(name: String, minutes: Int, color: Color)], totalMinutes: Int) {
        self.loads = loads
        self.totalMinutes = totalMinutes
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HOUSEHOLD DRIVING LOAD")
                        .font(HeliTypography.eyebrow(10))
                        .foregroundColor(HeliColors.mutedGray)
                        .tracking(1.4)
                    Text("\(totalMinutes / 60)h \(totalMinutes % 60)m total driving")
                        .font(HeliTypography.headline(18))
                        .foregroundColor(HeliColors.greenInk)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 11))
                    Text("Weekly")
                        .font(HeliTypography.chipLabel(11))
                }
                .foregroundColor(HeliColors.forestGreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(HeliColors.forestTint)
                .clipShape(Capsule())
            }

            // Stacked distribution bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if totalMinutes > 0 {
                        ForEach(loads, id: \.name) { item in
                            let fraction = CGFloat(item.minutes) / CGFloat(max(1, totalMinutes))
                            let width = max(4, fraction * (geo.size.width - CGFloat(loads.count - 1) * 2))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(item.color)
                                .frame(width: width, height: 12)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(HeliColors.sageRule)
                            .frame(width: geo.size.width, height: 12)
                    }
                }
            }
            .frame(height: 12)

            // Caregiver breakdown legend
            HStack(spacing: 12) {
                ForEach(loads, id: \.name) { item in
                    let pct = totalMinutes > 0 ? (item.minutes * 100) / totalMinutes : 0
                    HStack(spacing: 4) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 8, height: 8)
                        Text(item.name)
                            .font(HeliTypography.caption(11))
                            .foregroundColor(HeliColors.greenInk)
                        Text("\(item.minutes)m (\(pct)%)")
                            .font(HeliTypography.chipLabel(10))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                }
            }
        }
        .padding(16)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(HeliColors.sageRule, lineWidth: 0.8)
        )
        .padding(.horizontal, 16)
    }
}
