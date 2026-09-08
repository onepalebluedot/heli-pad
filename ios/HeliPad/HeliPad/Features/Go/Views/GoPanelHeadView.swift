import SwiftUI

public struct GoPanelHeadView: View {
    @ObservedObject var store: AppStore
    public var viewData: GoViewData

    public init(store: AppStore, viewData: GoViewData) {
        self.store = store
        self.viewData = viewData
    }

    public var body: some View {
        HStack(alignment: .center) {
            // Dynamic Title
            HStack(spacing: 8) {
                Text(titleText)
                    .font(HeliTypography.railTitle(16))
                    .foregroundColor(HeliColors.greenInk)

                // Completion Pips (only when on rail)
                if store.goPanel == "rail" {
                    HStack(spacing: 4) {
                        ForEach(viewData.plan, id: \.id) { analyzed in
                            Circle()
                                .fill(analyzed.event.done ? HeliColors.forestGreen : HeliColors.sageRule)
                                .frame(width: 5.5, height: 5.5)
                        }
                    }
                }
            }

            Spacer()

            // 2-Icon Panel Swap Toggle
            HStack(spacing: 2) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.goPanel = "rail"
                    }
                }) {
                    HeliIcon("list", size: 14)
                        .foregroundColor(store.goPanel == "rail" ? HeliColors.forestGreen : HeliColors.mutedGray)
                        .padding(6)
                        .background(store.goPanel == "rail" ? HeliColors.activeNavTab : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.goPanel = "load"
                    }
                }) {
                    HeliIcon("load", size: 14)
                        .foregroundColor(store.goPanel == "load" ? HeliColors.forestGreen : HeliColors.mutedGray)
                        .padding(6)
                        .background(store.goPanel == "load" ? HeliColors.activeNavTab : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(2)
            .background(HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(HeliColors.sageRule, lineWidth: 0.8)
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var titleText: String {
        if store.goPanel == "load" {
            return "Wheel time"
        }
        let who = store.goCrewFilter ?? store.currentUser
        if who == "All" {
            return "Today's family relay"
        }
        if who == store.currentUser {
            return viewData.live >= 0 ? "Rest of today" : "Today"
        }
        return "\(who)'s today"
    }
}
