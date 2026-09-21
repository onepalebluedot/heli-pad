import SwiftUI

#if os(iOS)

/// HeliPad's ivory, forest, and warm-card palette, shared by the lists screens.
enum Palette {
    static let canvas = Color(red: 0.965, green: 0.957, blue: 0.929)
    static let card = Color(red: 1, green: 0.996, blue: 0.973)
    static let forest = Color(red: 0.137, green: 0.341, blue: 0.275)
    static let ink = Color(red: 0.137, green: 0.239, blue: 0.2)
    static let muted = Color(red: 0.36, green: 0.415, blue: 0.37)
    static let rule = Color(red: 0.875, green: 0.886, blue: 0.84)
    static let sage = Color(red: 0.906, green: 0.933, blue: 0.875)
    static let butter = Color(red: 0.96, green: 0.946, blue: 0.85)
}

#endif
