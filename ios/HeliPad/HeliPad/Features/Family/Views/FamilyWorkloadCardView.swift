import SwiftUI

public struct FamilyWorkloadCardView: View {
    public var loads: [(name: String, drives: Int, color: Color)]
    public var totalDrives: Int

    public init(loads: [(name: String, drives: Int, color: Color)], totalDrives: Int) {
        self.loads = loads
        self.totalDrives = totalDrives
    }

    /// Only caregivers who actually drove get a segment and a legend entry. A
    /// zero-width segment still claimed the 4pt floor below, which read as a
    /// sliver of load that was not there.
    private var driving: [(name: String, drives: Int, color: Color)] {
        loads.filter { $0.drives > 0 }
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
                    Text("\(totalDrives) driving \(totalDrives == 1 ? "stop" : "stops")")
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
                    if totalDrives > 0 {
                        ForEach(driving, id: \.name) { item in
                            let fraction = CGFloat(item.drives) / CGFloat(max(1, totalDrives))
                            let width = max(4, fraction * (geo.size.width - CGFloat(driving.count - 1) * 2))
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
            if totalDrives > 0 {
                HStack(spacing: 12) {
                    ForEach(loads, id: \.name) { item in
                        let pct = (item.drives * 100) / totalDrives
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 8, height: 8)
                            Text(item.name)
                                .font(HeliTypography.caption(11))
                                .foregroundColor(HeliColors.greenInk)
                            Text("\(item.drives) (\(pct)%)")
                                .font(HeliTypography.chipLabel(10))
                                .foregroundColor(HeliColors.mutedGray)
                        }
                    }
                }
            } else {
                Text("No driving stops assigned this week yet.")
                    .font(HeliTypography.caption(11))
                    .foregroundColor(HeliColors.mutedGray)
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
