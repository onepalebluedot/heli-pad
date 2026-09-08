import SwiftUI

public extension Color {
    init(hex: String) {
        let hexClean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexClean).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexClean.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

public enum HeliColors {
    // Canvas & Structure
    public static let canvasIvory = Color(hex: "#f6f4ed")
    public static let cardWarmWhite = Color(hex: "#fffef8")
    public static let forestGreen = Color(hex: "#235746")
    public static let greenInk = Color(hex: "#233d33")
    public static let mutedGray = Color(hex: "#687469")
    public static let sageRule = Color(hex: "#dfe2d6")
    public static let butterYellow = Color(hex: "#e9e7bc")
    public static let sunOchre = Color(hex: "#ad722d")
    public static let warningClay = Color(hex: "#814d3c")
    public static let warningText = Color(hex: "#9a482c")
    public static let focusCopper = Color(hex: "#af612d")
    public static let highlightGold = Color(hex: "#ffd36b") // strictly reserved for now & started
    public static let activeNavTab = Color(hex: "#e7eedf")

    // Card Tones
    public static let toneForest = Color(hex: "#235746")
    public static let toneOlive = Color(hex: "#55532e")
    public static let toneClay = Color(hex: "#814d3c")

    // Ring Gradient Pairs [deep, bright]
    public static let ringLater = (deep: Color(hex: "#7cae5f"), bright: Color(hex: "#caeaa4"))
    public static let ringOntrack = (deep: Color(hex: "#7cae5f"), bright: Color(hex: "#caeaa4"))
    public static let ringSoon = (deep: Color(hex: "#cfa250"), bright: Color(hex: "#f7dc9a"))
    public static let ringNow = (deep: Color(hex: "#e39d33"), bright: Color(hex: "#ffd36b"))
    public static let ringStarted = (deep: Color(hex: "#e39d33"), bright: Color(hex: "#ffd36b"))
    public static let ringClear = (deep: Color(hex: "#7cae5f"), bright: Color(hex: "#caeaa4"))

    // Caregivers (Background, Text, and Ink)
    public struct PersonColor {
        public let bg: Color
        public let text: Color
        public let ink: Color
    }

    public static let mom = PersonColor(
        bg: Color(hex: "#f3c3b4"),
        text: Color(hex: "#7b2f20"),
        ink: Color(hex: "#c75f45")
    )
    public static let dad = PersonColor(
        bg: Color(hex: "#bad8f1"),
        text: Color(hex: "#174f7a"),
        ink: Color(hex: "#397cad")
    )
    public static let nani = PersonColor(
        bg: Color(hex: "#ddc2e9"),
        text: Color(hex: "#663879"),
        ink: Color(hex: "#8f55a0")
    )
    public static let grandma = PersonColor(
        bg: Color(hex: "#bfe0d4"),
        text: Color(hex: "#225d4d"),
        ink: Color(hex: "#3f806e")
    )
    public static let family = PersonColor(
        bg: Color(hex: "#f1d98f"),
        text: Color(hex: "#694900"),
        ink: Color(hex: "#b08313")
    )
    public static let tbd = PersonColor(
        bg: Color(hex: "#f0c69f"),
        text: Color(hex: "#7c3f17"),
        ink: Color(hex: "#bf6c2c")
    )

    public static let unknownPerson = PersonColor(
        bg: Color(hex: "#e5eadb"),
        text: Color(hex: "#314b37"),
        ink: Color(hex: "#93a58f")
    )

    /// Ink hex → the tone the design language pairs with it. A household set up
    /// with real names carries its ink on `Person.color`; this is how a name the
    /// palette has never heard of still reads as a distinct person.
    private static let tonesByInk: [String: PersonColor] = [
        "#c75f45": mom,
        "#397cad": dad,
        "#8f55a0": nani,
        "#3f806e": grandma,
        "#b08313": family,
        "#bf6c2c": tbd
    ]

    /// The tone the design language pairs with a person's assigned ink.
    public static func personColor(ink: String) -> PersonColor {
        return tonesByInk[ink.lowercased()] ?? unknownPerson
    }

    public static func personColor(for name: String) -> PersonColor {
        switch name {
        case "Mom": return mom
        case "Dad": return dad
        case "Nani": return nani
        case "Grandma": return grandma
        case "Family": return family
        case "TBD", "Unassigned": return tbd
        default:
            guard let ink = PersonInks.hex(for: name) else { return unknownPerson }
            return personColor(ink: ink)
        }
    }

    // Activity Categories
    public static let categorySports = Color(hex: "#7fa375")
    public static let categoryArts = Color(hex: "#bda170")
    public static let categorySocial = Color(hex: "#c2ba6b")
    public static let categorySchool = Color(hex: "#7f9fad")
    public static let categoryHealth = Color(hex: "#c98b6b")
    public static let categoryFamily = Color(hex: "#6b8f8a")

    public static let forestTint = Color(hex: "#e7eedf")
    public static let clayWash = Color(hex: "#f9ebe7")
    public static let clayText = Color(hex: "#814d3c")
    public static let ochreLight = Color(hex: "#f5e8d0")
    public static let ochreDark = Color(hex: "#ad722d")
    public static let butterLight = Color(hex: "#f7f6dc")

    public static func caregiverInk(_ name: String) -> Color {
        return personColor(for: name).ink
    }

    public static func categoryColor(for category: String) -> Color {
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

    public static func categoryColor(_ category: String) -> Color {
        return categoryColor(for: category)
    }
}


