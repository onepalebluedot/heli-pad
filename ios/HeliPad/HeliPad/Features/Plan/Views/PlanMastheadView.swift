import SwiftUI

public struct PlanMastheadView: View {
    public var weekRange: String
    public var onPrev: () -> Void
    public var onNext: () -> Void

    public init(weekRange: String, onPrev: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.weekRange = weekRange
        self.onPrev = onPrev
        self.onNext = onNext
    }

    public var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("7-day family plan")
                    .font(HeliTypography.eyebrow(10))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.4)
                Text(weekRange)
                    .font(HeliTypography.mastheadDate(26))
                    .foregroundColor(HeliColors.greenInk)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onPrev) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(HeliColors.greenInk)
                        .frame(width: 36, height: 36)
                        .background(HeliColors.cardWarmWhite)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(HeliColors.sageRule, lineWidth: 0.8))
                }

                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(HeliColors.greenInk)
                        .frame(width: 36, height: 36)
                        .background(HeliColors.cardWarmWhite)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(HeliColors.sageRule, lineWidth: 0.8))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}
