import SwiftUI

public struct FamilyPlacesView: View {
    public var locations: [LocationItem]
    public var caregivers: [Person]
    public var onSelectLocation: (LocationItem) -> Void
    public var onAddLocation: () -> Void

    public init(
        locations: [LocationItem],
        caregivers: [Person],
        onSelectLocation: @escaping (LocationItem) -> Void,
        onAddLocation: @escaping () -> Void
    ) {
        self.locations = locations
        self.caregivers = caregivers
        self.onSelectLocation = onSelectLocation
        self.onAddLocation = onAddLocation
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                Text("REGULAR PLACES")
                    .font(HeliTypography.eyebrow(11))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.4)

                Spacer()

                Button(action: onAddLocation) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add Place")
                            .font(HeliTypography.actionButton(11))
                    }
                    .foregroundColor(HeliColors.forestGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(HeliColors.forestTint)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)

            // Caregiver Bases Summary Card
            VStack(alignment: .leading, spacing: 12) {
                Text("STARTING BASES")
                    .font(HeliTypography.eyebrow(10))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.2)

                VStack(spacing: 8) {
                    ForEach(caregivers) { p in
                        HStack {
                            AvatarDisc(name: p.name, size: 22)
                            Text(p.name)
                                .font(HeliTypography.headline(13))
                                .foregroundColor(HeliColors.greenInk)
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "house")
                                    .font(.system(size: 10))
                                Text(p.baseLocation ?? "Home")
                                    .font(HeliTypography.caption(12))
                            }
                            .foregroundColor(HeliColors.mutedGray)
                        }
                    }
                }
            }
            .padding(16)
            .background(HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(HeliColors.sageRule, lineWidth: 0.8))
            .padding(.horizontal, 16)

            // Saved Locations List
            VStack(alignment: .leading, spacing: 10) {
                Text("ALL SAVED VENUES (\(locations.count))")
                    .font(HeliTypography.eyebrow(10))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.2)
                    .padding(.horizontal, 20)

                VStack(spacing: 8) {
                    ForEach(locations) { loc in
                        locationRow(loc: loc)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func locationRow(loc: LocationItem) -> some View {
        Button(action: { onSelectLocation(loc) }) {
            HStack(alignment: .center, spacing: 12) {
                // Icon
                Image(systemName: locationIcon(loc.name))
                    .font(.system(size: 14))
                    .foregroundColor(HeliColors.forestGreen)
                    .frame(width: 32, height: 32)
                    .background(HeliColors.forestTint)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.name)
                        .font(HeliTypography.cardTitle(14))
                        .foregroundColor(HeliColors.greenInk)
                    Text(loc.address)
                        .font(HeliTypography.caption(12))
                        .foregroundColor(HeliColors.mutedGray)
                        .lineLimit(1)
                }

                Spacer()

                if let rk = loc.routeKey, !rk.isEmpty {
                    Text("Calibrated")
                        .font(HeliTypography.eyebrow(9))
                        .foregroundColor(HeliColors.forestGreen)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(HeliColors.forestTint)
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(HeliColors.mutedGray)
            }
            .padding(12)
            .background(HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(HeliColors.sageRule, lineWidth: 0.8))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func locationIcon(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("home") { return "house.fill" }
        if n.contains("school") || n.contains("high") || n.contains("elementary") { return "graduationcap.fill" }
        if n.contains("park") || n.contains("field") || n.contains("soccer") { return "sportscourt.fill" }
        if n.contains("pool") || n.contains("aquatic") { return "water.waves" }
        if n.contains("dance") || n.contains("arts") || n.contains("studio") { return "music.note" }
        if n.contains("clinic") || n.contains("pediatric") { return "cross.case.fill" }
        return "mappin.and.ellipse"
    }
}
