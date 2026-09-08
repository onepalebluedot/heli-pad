import SwiftUI

public struct GoMastheadView: View {
    public var todayIdx: Int
    @ObservedObject public var store: AppStore

    private let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    public init(todayIdx: Int = 0, store: AppStore? = nil) {
        self.todayIdx = todayIdx
        self.store = store ?? AppStore.shared
    }

    private static let dayDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMM d"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df
    }()

    private static let inputDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df
    }()

    private func formattedDate(for index: Int) -> String {
        let dateStr = store.dateForDay(index)
        if let d = Self.inputDateFormatter.date(from: dateStr) {
            return Self.dayDateFormatter.string(from: d)
        }
        let safeIdx = ((index % 7) + 7) % 7
        return dayNames[safeIdx]
    }

    public var body: some View {
        let safeIdx = ((todayIdx % 7) + 7) % 7
        let weather = store.liveWeather
        let isToday = (safeIdx == store.todayIndex)

        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isToday ? "TODAY" : "SCHEDULE")
                    .font(HeliTypography.eyebrow(10))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.4)
                Text(formattedDate(for: safeIdx))
                    .font(HeliTypography.mastheadDate(26))
                    .foregroundColor(HeliColors.greenInk)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    HeliIcon(weather.icon, size: 26)
                        .foregroundColor(HeliColors.sunOchre)
                        .rotationEffect(.degrees(-10))
                    Text(weather.tempRangeDisplay)
                        .font(HeliTypography.monoTime(15))
                        .foregroundColor(HeliColors.greenInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Text(weather.condition)
                    .font(HeliTypography.eyebrow(9.5))
                    .foregroundColor(HeliColors.mutedGray)
            }
            .accessibilityLabel("Today: \(weather.label)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}
