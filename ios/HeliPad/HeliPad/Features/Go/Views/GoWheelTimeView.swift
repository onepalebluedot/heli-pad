import SwiftUI

public struct GoWheelTimeView: View {
    public var drivers: [String: Int]
    public var currentUser: String

    public init(drivers: [String: Int], currentUser: String = "All") {
        self.drivers = drivers
        self.currentUser = currentUser
    }

    public var body: some View {
        let active = drivers.filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
        let maxMinutes = max(1, active.first?.value ?? 1)

        VStack(spacing: 12) {
            if active.isEmpty {
                Text("No driving assigned yet today.")
                    .font(HeliTypography.body(14))
                    .foregroundColor(HeliColors.mutedGray)
                    .padding(.vertical, 20)
            } else {
                ForEach(active, id: \.key) { (name, mins) in
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

                                let fillWidth = geo.size.width * CGFloat(Double(mins) / Double(maxMinutes))
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(col.ink)
                                    .frame(width: max(8, fillWidth), height: 10)
                            }
                        }
                        .frame(height: 10)

                        Text(TimeFormat.formatDurationShort(mins))
                            .font(HeliTypography.railTime(13))
                            .foregroundColor(HeliColors.greenInk)
                            .frame(width: 56, alignment: .trailing)
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
