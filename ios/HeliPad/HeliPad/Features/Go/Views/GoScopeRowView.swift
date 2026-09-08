import SwiftUI

public struct GoScopeRowView: View {
    @ObservedObject var store: AppStore

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Segments Row
            HStack(spacing: 8) {
                // Caregiver Scope Segment
                let who = store.goCrewFilter ?? store.currentUser
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.goScopeOpen = (store.goScopeOpen == "crew") ? nil : "crew"
                    }
                }) {
                    HStack(spacing: 8) {
                        AvatarDisc(name: who, size: 24)
                        Text(who == store.currentUser ? "Me" : (who == "All" ? "Everyone" : who))
                            .font(HeliTypography.railTitle(13))
                            .foregroundColor(HeliColors.greenInk)
                        Spacer()
                        Image(systemName: store.goScopeOpen == "crew" ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(store.goScopeOpen == "crew" ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: 1)
                    )
                }

                // Kid Scope Segment
                let kid = store.goKidFilter
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.goScopeOpen = (store.goScopeOpen == "kid") ? nil : "kid"
                    }
                }) {
                    HStack(spacing: 8) {
                        HeliIcon("user-round", size: 13)
                            .foregroundColor(HeliColors.greenInk)
                        Text(kid == "all" || kid == "All" ? "Kids" : kid)
                            .font(HeliTypography.railTitle(13))
                            .foregroundColor(HeliColors.greenInk)
                        Spacer()
                        Image(systemName: store.goScopeOpen == "kid" ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(store.goScopeOpen == "kid" ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: 1)
                    )
                }
            }

            // Swapped Drawer
            if let open = store.goScopeOpen {
                if open == "crew" {
                    crewDrawer
                } else if open == "kid" {
                    kidDrawer
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var crewDrawer: some View {
        HStack(spacing: 8) {
            ForEach(store.caregivers(), id: \.self) { name in
                let selected = (store.goCrewFilter == name) || (store.goCrewFilter == nil && store.currentUser == name)
                Button(action: {
                    store.goCrewFilter = (name == store.currentUser) ? nil : name
                    withAnimation { store.goScopeOpen = nil }
                }) {
                    VStack(spacing: 4) {
                        AvatarDisc(name: name, size: 28)
                        Text(name == store.currentUser ? "Me" : name)
                            .font(HeliTypography.railMeta(11))
                            .foregroundColor(selected ? HeliColors.forestGreen : HeliColors.greenInk)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(selected ? HeliColors.activeNavTab : HeliColors.cardWarmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            // Everyone option
            let isAll = (store.goCrewFilter == "All")
            Button(action: {
                store.goCrewFilter = "All"
                withAnimation { store.goScopeOpen = nil }
            }) {
                VStack(spacing: 4) {
                    AvatarDisc(name: "Family", size: 28)
                    Text("Everyone")
                        .font(HeliTypography.railMeta(11))
                        .foregroundColor(isAll ? HeliColors.forestGreen : HeliColors.greenInk)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(isAll ? HeliColors.activeNavTab : HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(10)
        .background(HeliColors.cardWarmWhite.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var kidDrawer: some View {
        HStack(spacing: 8) {
            Button(action: {
                store.goKidFilter = "all"
                withAnimation { store.goScopeOpen = nil }
            }) {
                HStack(spacing: 4) {
                    HeliIcon("users-round", size: 12)
                    Text("All kids")
                        .font(HeliTypography.railMeta(12))
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .foregroundColor(store.goKidFilter == "all" ? HeliColors.forestGreen : HeliColors.greenInk)
                .background(store.goKidFilter == "all" ? HeliColors.activeNavTab : HeliColors.cardWarmWhite)
                .clipShape(Capsule())
            }

            ForEach(store.children(), id: \.self) { child in
                let selected = (store.goKidFilter == child)
                Button(action: {
                    store.goKidFilter = child
                    withAnimation { store.goScopeOpen = nil }
                }) {
                    HStack(spacing: 4) {
                        HeliIcon("user-round", size: 12)
                        Text(child)
                            .font(HeliTypography.railMeta(12))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .foregroundColor(selected ? HeliColors.forestGreen : HeliColors.greenInk)
                    .background(selected ? HeliColors.activeNavTab : HeliColors.cardWarmWhite)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(10)
        .background(HeliColors.cardWarmWhite.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
