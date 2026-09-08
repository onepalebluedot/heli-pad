import SwiftUI

public enum HeliTypography {
    // Serif Editorial Font (Georgia / Newsreader style)
    public static func serifTitle(_ size: CGFloat = 28, weight: Font.Weight = .regular) -> Font {
        return Font.system(size: size, weight: weight, design: .serif)
    }

    public static func mastheadDate(_ size: CGFloat = 26) -> Font {
        return Font.system(size: size, weight: .regular, design: .serif)
    }

    public static func rosterName(_ size: CGFloat = 24) -> Font {
        return Font.system(size: size, weight: .medium, design: .serif)
    }

    public static func destTitle(_ size: CGFloat = 21) -> Font {
        return Font.system(size: size, weight: .bold, design: .default)
    }

    // Sans-Serif Operational Fonts
    public static func countdownNum(_ size: CGFloat = 56) -> Font {
        return Font.system(size: size, weight: .bold, design: .default)
    }

    public static func countdownWord(_ size: CGFloat = 30) -> Font {
        return Font.system(size: size, weight: .heavy, design: .default)
    }

    public static func hoursNum(_ size: CGFloat = 44) -> Font {
        return Font.system(size: size, weight: .bold, design: .default)
    }

    public static func dialUnit(_ size: CGFloat = 9.5) -> Font {
        return Font.system(size: size, weight: .heavy, design: .default)
    }

    public static func eyebrow(_ size: CGFloat = 10) -> Font {
        return Font.system(size: size, weight: .heavy, design: .default)
    }

    public static func railTime(_ size: CGFloat = 14) -> Font {
        return Font.system(size: size, weight: .bold, design: .default)
    }

    public static func railTitle(_ size: CGFloat = 13.5) -> Font {
        return Font.system(size: size, weight: .heavy, design: .default)
    }

    public static func railMeta(_ size: CGFloat = 12) -> Font {
        return Font.system(size: size, weight: .medium, design: .default)
    }

    public static func railLeave(_ size: CGFloat = 11.5) -> Font {
        return Font.system(size: size, weight: .semibold, design: .default)
    }

    public static func body(_ size: CGFloat = 14) -> Font {
        return Font.system(size: size, weight: .regular, design: .default)
    }

    public static func headline(_ size: CGFloat = 18) -> Font {
        return Font.system(size: size, weight: .bold, design: .default)
    }

    public static func cardTitle(_ size: CGFloat = 14) -> Font {
        return Font.system(size: size, weight: .semibold, design: .default)
    }

    public static func chipLabel(_ size: CGFloat = 11) -> Font {
        return Font.system(size: size, weight: .medium, design: .default)
    }

    public static func actionButton(_ size: CGFloat = 13) -> Font {
        return Font.system(size: size, weight: .semibold, design: .default)
    }

    public static func caption(_ size: CGFloat = 11) -> Font {
        return Font.system(size: size, weight: .regular, design: .default)
    }

    public static func monoTime(_ size: CGFloat = 12) -> Font {
        return Font.system(size: size, weight: .medium, design: .monospaced)
    }

    public static func buttonLabel(_ size: CGFloat = 14.5) -> Font {
        return Font.system(size: size, weight: .semibold, design: .default)
    }
}

