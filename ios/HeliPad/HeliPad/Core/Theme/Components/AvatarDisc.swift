import SwiftUI

public struct AvatarDisc: View {
    public var name: String
    public var size: CGFloat
    public var showNameBelow: Bool
    public var isKid: Bool
    /// An explicit ink, for people who are not on the roster yet — the setup
    /// flow draws its draft household before the store has ever seen it.
    public var colorHex: String?

    public init(
        name: String,
        size: CGFloat = 35,
        showNameBelow: Bool = false,
        isKid: Bool = false,
        colorHex: String? = nil
    ) {
        self.name = name
        self.size = size
        self.showNameBelow = showNameBelow
        self.isKid = isKid
        self.colorHex = colorHex
    }

    public var isTBD: Bool {
        return name == "TBD" || name == "Unassigned" || name.isEmpty
    }

    public var initial: String {
        if isTBD { return "?" }
        if name == "Family" { return size <= 26 ? "All" : "F" }
        return String(name.prefix(1))
    }

    public var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isKid {
                    Circle()
                        .fill(HeliColors.butterYellow)
                    HeliIcon("user-round", size: size * 0.5)
                        .foregroundColor(HeliColors.greenInk)
                } else if isTBD {
                    Circle()
                        .fill(HeliColors.tbd.bg)
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                        .foregroundColor(HeliColors.tbd.ink)
                    Text("?")
                        .font(.system(size: size * 0.46, weight: .bold))
                        .foregroundColor(HeliColors.tbd.text)
                } else {
                    let col = colorHex.map { HeliColors.personColor(ink: $0) }
                        ?? HeliColors.personColor(for: name)
                    Circle()
                        .fill(col.bg)
                    Circle()
                        .stroke(col.ink.opacity(0.35), lineWidth: 0.8)
                    Text(initial)
                        .font(.system(size: size * 0.44, weight: .bold))
                        .foregroundColor(col.text)
                }
            }
            .frame(width: size, height: size)

            if showNameBelow {
                Text(isTBD ? "Assign" : name)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(isTBD ? HeliColors.tbd.text : HeliColors.greenInk)
                    .lineLimit(1)
            }
        }
    }
}
