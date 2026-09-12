import SwiftUI

public struct GoWheelTimeView: View {
    public var drivers: [String: DriverLoad]
    public var currentUser: String

    public init(drivers: [String: DriverLoad], currentUser: String = "All") {
        self.drivers = drivers
        self.currentUser = currentUser
    }

    public var body: some View {
        let active = drivers.filter { $0.value.assignedStops > 0 }
            .sorted { lhs, rhs in
                if lhs.value.minutes != rhs.value.minutes { return lhs.value.minutes > rhs.value.minutes }
                return lhs.value.assignedStops > rhs.value.assignedStops
            }
        let maxMinutes = max(1, active.map(\.value.minutes).max() ?? 1)

        VStack(spacing: 12) {
            if active.isEmpty {
                Text("No driving assigned yet today.")
                    .font(HeliTypography.body(14))
                    .foregroundColor(HeliColors.mutedGray)
                    .padding(.vertical, 20)
            } else {
                ForEach(active, id: \.key) { (name, load) in
                    let col = HeliColors.personColor(for: name)
                    HStack(spacing: 12) {
                        AvatarDisc(name: name, size: 28)
                            .frame(width: 36)

                        Text(name == currentUser ? "You" : name)
                            .font(HeliTypography.railTitle(13))
                            .foregroundColor(HeliColors.greenInk)
                            .frame(width: 50, alignment: .leading)

                        // Track bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(HeliColors.cardWarmWhite)
                                    .frame(height: 10)

                                let fillWidth = geo.size.width * CGFloat(Double(load.minutes) / Double(maxMinutes))
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(col.ink)
                                    .frame(width: max(8, fillWidth), height: 10)
                            }
                        }
                        .frame(height: 10)

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(load.knownRoutes == 0 ? "Route needed" : TimeFormat.formatDurationShort(load.minutes))
                                .font(HeliTypography.railTime(12))
                            Text(load.unknownRoutes > 0 ? "partial · \(load.assignedStops) stops" : "\(load.assignedStops) stops")
                                .font(HeliTypography.caption(9.5))
                                .foregroundColor(HeliColors.mutedGray)
                        }
                        .foregroundColor(HeliColors.greenInk)
                        .frame(width: 86, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20)
    }
}
