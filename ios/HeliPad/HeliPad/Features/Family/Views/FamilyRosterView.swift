import SwiftUI

public struct FamilyRosterView: View {
    public var caregivers: [Person]
    /// Driving stops per caregiver for the week, keyed by name.
    public var loads: [String: Int]
    public var settings: [String: Any]
    public var onEditRules: () -> Void

    public init(
        caregivers: [Person],
        loads: [String: Int],
        settings: [String: Any],
        onEditRules: @escaping () -> Void
    ) {
        self.caregivers = caregivers
        self.loads = loads
        self.settings = settings
        self.onEditRules = onEditRules
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                Text("CAREGIVERS ROSTER")
                    .font(HeliTypography.eyebrow(11))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.4)
                Spacer()
            }
            .padding(.horizontal, 20)

            // Caregiver Cards
            VStack(spacing: 10) {
                ForEach(caregivers) { p in
                    caregiverCard(person: p, drives: loads[p.name] ?? 0)
                }
            }
            .padding(.horizontal, 16)

            // Shared Planning Rules Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("SHARED PLANNING RULES")
                        .font(HeliTypography.eyebrow(10))
                        .foregroundColor(HeliColors.mutedGray)
                        .tracking(1.2)
                    Spacer()
                    Button(action: onEditRules) {
                        Text("Edit Rules")
                            .font(HeliTypography.actionButton(11))
                            .foregroundColor(HeliColors.forestGreen)
                    }
                }

                VStack(spacing: 8) {
                    ruleRow(
                        icon: "clock.arrow.circlepath",
                        title: "Buffer Between Stops",
                        value: "\(settings["bufferMinutes"] as? Int ?? 10) min"
                    )
                    ruleRow(
                        icon: "car.side.fill",
                        title: "Peak Traffic Calibration",
                        value: (settings["peakTraffic"] as? Bool ?? true) ? "1.15x Active" : "Disabled"
                    )
                    ruleRow(
                        icon: "fork.knife",
                        title: "Dinner Protection",
                        value: (settings["dinnerProtected"] as? Bool ?? true) ? "\(settings["dinnerTime"] as? String ?? "18:00") Target" : "Disabled"
                    )
                }
            }
            .padding(16)
            .background(HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(HeliColors.sageRule, lineWidth: 0.8))
            .padding(.horizontal, 16)
        }
    }

    private func caregiverCard(person: Person, drives: Int) -> some View {
        HStack(alignment: .center, spacing: 14) {
            AvatarDisc(name: person.name, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(person.name)
                    .font(HeliTypography.headline(16))
                    .foregroundColor(HeliColors.greenInk)

                HStack(spacing: 6) {
                    Text(person.role.capitalized)
                        .font(HeliTypography.caption(12))
                        .foregroundColor(HeliColors.mutedGray)

                    Text("•")
                        .foregroundColor(HeliColors.sageRule)

                    Text("Base: \(person.baseLocation ?? "Home")")
                        .font(HeliTypography.caption(12))
                        .foregroundColor(HeliColors.mutedGray)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(drives)")
                    .font(HeliTypography.headline(15))
                    .foregroundColor(HeliColors.forestGreen)
                Text(drives == 1 ? "driving stop" : "driving stops")
                    .font(HeliTypography.caption(10))
                    .foregroundColor(HeliColors.mutedGray)
            }
        }
        .padding(14)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(HeliColors.sageRule, lineWidth: 0.8))
    }

    private func ruleRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(HeliColors.forestGreen)
                .frame(width: 20)

            Text(title)
                .font(HeliTypography.body(13))
                .foregroundColor(HeliColors.greenInk)

            Spacer()

            Text(value)
                .font(HeliTypography.caption(12))
                .foregroundColor(HeliColors.mutedGray)
        }
    }
}
