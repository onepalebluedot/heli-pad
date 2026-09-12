import SwiftUI

// MARK: - Theme mirror
//
// These values are copied from the app's `Core/Theme/HeliColors.swift`,
// `HeliTypography.swift` and `Components/HeliCard.swift`. They are duplicated
// rather than imported because this work stream deliberately does not depend on
// the app target.
//
// At integration this file is deleted and the views use the app's own theme
// directly - the names below match the originals one for one so that is a
// find-and-replace, not a redesign. Until then, a change to the app's palette
// has to be mirrored here by hand.

extension Color {
    init(heliHex hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        let r, g, b: UInt64
        switch clean.count {
        case 3: (r, g, b) = ((value >> 8) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17)
        case 6: (r, g, b) = (value >> 16, value >> 8 & 0xFF, value & 0xFF)
        default: (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}

enum HeliColors {
    static let canvasIvory = Color(heliHex: "#f6f4ed")
    static let cardWarmWhite = Color(heliHex: "#fffef8")
    static let forestGreen = Color(heliHex: "#235746")
    static let greenInk = Color(heliHex: "#233d33")
    static let mutedGray = Color(heliHex: "#687469")
    static let sageRule = Color(heliHex: "#dfe2d6")
    static let sunOchre = Color(heliHex: "#ad722d")
    static let warningClay = Color(heliHex: "#814d3c")
    static let warningText = Color(heliHex: "#9a482c")
    static let focusCopper = Color(heliHex: "#af612d")
    static let forestTint = Color(heliHex: "#e7eedf")
    static let clayWash = Color(heliHex: "#f9ebe7")
    static let ochreLight = Color(heliHex: "#f5e8d0")
    static let butterLight = Color(heliHex: "#f7f6dc")

    // Caregiver tones, used to ink an owner chip the way the roster does.
    struct PersonColor {
        let bg: Color
        let text: Color
        let ink: Color
    }

    static let mom = PersonColor(bg: Color(heliHex: "#f3c3b4"), text: Color(heliHex: "#7b2f20"), ink: Color(heliHex: "#c75f45"))
    static let dad = PersonColor(bg: Color(heliHex: "#bad8f1"), text: Color(heliHex: "#174f7a"), ink: Color(heliHex: "#397cad"))
    static let nani = PersonColor(bg: Color(heliHex: "#ddc2e9"), text: Color(heliHex: "#663879"), ink: Color(heliHex: "#8f55a0"))
    static let grandma = PersonColor(bg: Color(heliHex: "#bfe0d4"), text: Color(heliHex: "#225d4d"), ink: Color(heliHex: "#3f806e"))
    static let family = PersonColor(bg: Color(heliHex: "#f1d98f"), text: Color(heliHex: "#694900"), ink: Color(heliHex: "#b08313"))
    static let tbd = PersonColor(bg: Color(heliHex: "#f0c69f"), text: Color(heliHex: "#7c3f17"), ink: Color(heliHex: "#bf6c2c"))
    static let unknownPerson = PersonColor(bg: Color(heliHex: "#e5eadb"), text: Color(heliHex: "#314b37"), ink: Color(heliHex: "#93a58f"))

    /// The app resolves unknown names through `PersonInks`, which is populated
    /// from the household. Here the fixture names are matched directly, and
    /// anything else falls through to the neutral tone - same outcome, minus a
    /// dependency on app state.
    static func personColor(for name: String) -> PersonColor {
        switch name {
        case "Mom", "Maya": return mom
        case "Dad", "Alex": return dad
        case "Nani": return nani
        case "Grandma": return grandma
        case "Family": return family
        case "TBD", "Unassigned", "Needs a driver": return tbd
        default: return unknownPerson
        }
    }

    static let categorySports = Color(heliHex: "#7fa375")
    static let categoryArts = Color(heliHex: "#bda170")
    static let categorySocial = Color(heliHex: "#c2ba6b")
    static let categorySchool = Color(heliHex: "#7f9fad")
    static let categoryHealth = Color(heliHex: "#c98b6b")
    static let categoryFamily = Color(heliHex: "#6b8f8a")

    static func categoryColor(for category: String) -> Color {
        switch category.lowercased() {
        case "sports": return categorySports
        case "arts", "arts & music": return categoryArts
        case "social", "family & social": return categorySocial
        case "family": return categoryFamily
        case "school": return categorySchool
        case "health": return categoryHealth
        case "other": return mutedGray
        default: return categorySports
        }
    }
}

enum HeliTypography {
    static func serifTitle(_ size: CGFloat = 28, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .serif)
    }
    static func rosterName(_ size: CGFloat = 24) -> Font {
        Font.system(size: size, weight: .medium, design: .serif)
    }
    static func eyebrow(_ size: CGFloat = 10) -> Font {
        Font.system(size: size, weight: .heavy, design: .default)
    }
    static func railTime(_ size: CGFloat = 14) -> Font {
        Font.system(size: size, weight: .bold, design: .default)
    }
    static func railTitle(_ size: CGFloat = 13.5) -> Font {
        Font.system(size: size, weight: .heavy, design: .default)
    }
    static func railMeta(_ size: CGFloat = 12) -> Font {
        Font.system(size: size, weight: .medium, design: .default)
    }
    static func body(_ size: CGFloat = 14) -> Font {
        Font.system(size: size, weight: .regular, design: .default)
    }
    static func headline(_ size: CGFloat = 18) -> Font {
        Font.system(size: size, weight: .bold, design: .default)
    }
    static func cardTitle(_ size: CGFloat = 14) -> Font {
        Font.system(size: size, weight: .semibold, design: .default)
    }
    static func chipLabel(_ size: CGFloat = 11) -> Font {
        Font.system(size: size, weight: .medium, design: .default)
    }
    static func actionButton(_ size: CGFloat = 13) -> Font {
        Font.system(size: size, weight: .semibold, design: .default)
    }
    static func caption(_ size: CGFloat = 11) -> Font {
        Font.system(size: size, weight: .regular, design: .default)
    }
    static func monoTime(_ size: CGFloat = 12) -> Font {
        Font.system(size: size, weight: .medium, design: .monospaced)
    }
    static func buttonLabel(_ size: CGFloat = 14.5) -> Font {
        Font.system(size: size, weight: .semibold, design: .default)
    }
}

/// Mirrors `Core/Theme/Components/HeliCard.swift`.
struct HeliCard<Content: View>: View {
    var cornerRadius: CGFloat = 26
    var backgroundColor: Color = HeliColors.cardWarmWhite
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(HeliColors.sageRule.opacity(0.6), lineWidth: 0.8)
            )
    }
}

/// The app's small-caps section label: heavy, uppercase, widely tracked.
struct Eyebrow: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = HeliColors.mutedGray

    var body: some View {
        Text(text.uppercased())
            .font(HeliTypography.eyebrow(size))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

/// Lucide-style name onto an SF Symbol, the same indirection the app uses in
/// `Core/Theme/HeliIcons.swift`. Keeping the names aligned means the views read
/// the same in both places.
struct HeliIcon: View {
    let name: String
    var size: CGFloat = 16
    var weight: Font.Weight = .semibold

    var body: some View {
        Image(systemName: Self.symbol(for: name))
            .font(.system(size: size, weight: weight))
    }

    static func symbol(for name: String) -> String {
        switch name.lowercased() {
        case "calendar-days", "calendar": return "calendar"
        case "users-round", "people": return "person.2"
        case "user-round", "user": return "person"
        case "house", "home": return "house"
        case "map-pin", "place": return "mappin.and.ellipse"
        case "check", "checkmark": return "checkmark"
        case "circle-check": return "checkmark.circle.fill"
        case "x", "close": return "xmark"
        case "triangle-alert", "warning": return "exclamationmark.triangle.fill"
        case "info": return "info.circle"
        case "repeat-2", "repeat": return "repeat"
        case "arrow-up", "send": return "arrow.up"
        case "square", "stop": return "stop.fill"
        case "trash": return "trash"
        case "sparkles", "assistant": return "bubble.left.and.text.bubble.right"
        case "chart", "trends": return "chart.bar"
        case "lock", "private": return "lock"
        case "chevron-right": return "chevron.right"
        case "ellipsis": return "ellipsis"
        default: return "circle"
        }
    }
}
