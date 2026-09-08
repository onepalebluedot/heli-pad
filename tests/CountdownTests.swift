import Foundation

@main
struct CountdownTests {
    static func main() {
        let cases: [(Int, Double)] = [
            (220, 1), (60, 1), (31, 1), (30, 1),
            (29, 29.0 / 30), (15, 0.5), (1, 1.0 / 30),
            (0, 0), (-1, 0), (-20, 0)
        ]
        for (minutes, expected) in cases {
            precondition(
                abs(TimeFormat.countdownFraction(minutesUntil: minutes) - expected) < 0.000001,
                "Unexpected ring fill at \(minutes) minutes"
            )
        }
        precondition(TimeFormat.formatDurationShort(220) == "3h 40m")
        precondition(TimeFormat.formatDurationShort(600) == "10h")
        print("Countdown boundary and duration checks passed.")
    }
}
