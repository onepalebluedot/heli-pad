import SwiftUI

public struct HeliIcon: View {
    public var name: String
    public var size: CGFloat
    public var strokeWidth: CGFloat

    public init(_ name: String, size: CGFloat = 16, strokeWidth: CGFloat = 1.6) {
        self.name = name
        self.size = size
        self.strokeWidth = strokeWidth
    }

    public var body: some View {
        Group {
            switch name.lowercased() {
            case "navigation", "go":
                Image(systemName: "location.north.fill")
            case "calendar-days", "calendar", "plan":
                Image(systemName: "calendar")
            case "users-round", "users", "people":
                Image(systemName: "person.2")
            case "user-round", "user", "child":
                Image(systemName: "person")
            case "house", "home":
                Image(systemName: "house")
            case "car-front", "drive", "car":
                Image(systemName: "car")
            case "person-standing", "walk":
                Image(systemName: "figure.walk")
            case "bus-front", "bus", "school bus":
                Image(systemName: "bus")
            case "carpool":
                Image(systemName: "person.2")
            case "list", "rail":
                Image(systemName: "list.bullet")
            case "chart-no-axes-column", "load":
                Image(systemName: "chart.bar")
            case "check", "checkmark":
                Image(systemName: "checkmark")
            case "plus":
                Image(systemName: "plus")
            case "x", "close":
                Image(systemName: "xmark")
            case "pencil", "edit":
                Image(systemName: "pencil")
            case "arrow-right":
                Image(systemName: "arrow.right")
            case "repeat-2", "repeat":
                Image(systemName: "repeat")
            case "sun":
                Image(systemName: "sun.max")
            case "partly":
                Image(systemName: "cloud.sun")
            case "cloud":
                Image(systemName: "cloud")
            case "rain":
                Image(systemName: "cloud.rain")
            case "storm":
                Image(systemName: "cloud.bolt")
            case "moon":
                Image(systemName: "moon")
            case "school":
                Image(systemName: "building.columns")
            case "music", "music-2", "lesson":
                Image(systemName: "music.note")
            case "ball", "practice":
                Image(systemName: "sportscourt")
            case "care", "clinic", "health":
                Image(systemName: "cross.case")
            case "play", "playdate":
                Image(systemName: "paintpalette")
            case "meal", "dinner":
                Image(systemName: "fork.knife")
            case "gear", "settings":
                Image(systemName: "gearshape")
            case "alert", "triangle-alert":
                Image(systemName: "exclamationmark.triangle")
            case "map-pin", "pin", "place":
                Image(systemName: "mappin.and.ellipse")
            case "building-2", "briefcase", "work":
                Image(systemName: "building.2")
            case "factory":
                Image(systemName: "gearshape.2")
            case "trophy", "sports":
                Image(systemName: "trophy")
            case "goal", "field":
                Image(systemName: "flag")
            case "hospital":
                Image(systemName: "cross.case.fill")
            case "store", "shopping-cart", "shop":
                Image(systemName: "cart")
            case "sparkles", "wand":
                Image(systemName: "sparkles")
            case "trash", "delete":
                Image(systemName: "trash")
            case "arrow-left":
                Image(systemName: "arrow.left")
            case "clock":
                Image(systemName: "clock")
            case "rotate-ccw", "restart":
                Image(systemName: "arrow.counterclockwise")
            case "palmtree", "activity":
                Image(systemName: "figure.run")
            case "chevron-left":
                Image(systemName: "chevron.left")
            case "chevron-right":
                Image(systemName: "chevron.right")
            case "chevron-down":
                Image(systemName: "chevron.down")
            case "chevron-up":
                Image(systemName: "chevron.up")
            default:
                Image(systemName: "circle")
            }
        }
        .font(.system(size: size, weight: .semibold))
    }
}

public enum HeliIcons {
    public static func icon(name: String, size: CGFloat = 16, color: Color = .primary) -> some View {
        HeliIcon(name, size: size).foregroundColor(color)
    }
}

