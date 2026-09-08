import SwiftUI

public struct GoDialInstrument: View {
    public var fraction: Double
    public var tone: UrgencyTone
    public var centerTitle: String
    public var centerUnit: String
    public var isWord: Bool
    public var isHours: Bool

    @State private var breathPhase: Bool = false

    public init(
        fraction: Double,
        tone: UrgencyTone = .later,
        centerTitle: String,
        centerUnit: String,
        isWord: Bool = false,
        isHours: Bool = false
    ) {
        self.fraction = max(0, min(1, fraction))
        self.tone = tone
        self.centerTitle = centerTitle
        self.centerUnit = centerUnit
        self.isWord = isWord
        self.isHours = isHours
    }

    private var colors: (deep: Color, bright: Color) {
        switch tone {
        case .now, .started:
            return HeliColors.ringNow
        case .soon:
            return HeliColors.ringSoon
        default:
            return HeliColors.ringLater
        }
    }

    public var body: some View {
        ZStack {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: size / 2, y: size / 2)
                let radius = size * 0.43 // ~86 on a 200px box
                let lineWidth = size * 0.06 // ~12 on 200px

                // 12 Hour Ticks
                ForEach(0..<12, id: \.self) { i in
                    let angle = Double(i) * (.pi / 6)
                    let cosA = cos(angle)
                    let sinA = sin(angle)
                    let r1 = radius - (i % 3 == 0 ? size * 0.06 : size * 0.04)
                    let r2 = radius - size * 0.015

                    Path { path in
                        path.move(to: CGPoint(x: center.x + r1 * cosA, y: center.y + r1 * sinA))
                        path.addLine(to: CGPoint(x: center.x + r2 * cosA, y: center.y + r2 * sinA))
                    }
                    .stroke(
                        Color.white.opacity(i % 3 == 0 ? 0.35 : 0.18),
                        lineWidth: i % 3 == 0 ? 2 : 1.2
                    )
                }

                // Base Track Ring
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: lineWidth)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)

                // Leading Arc
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [colors.deep, colors.bright]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + 360 * fraction)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)

                // Leading Bead
                if fraction > 0.015 && fraction < 0.995 {
                    let angle = fraction * 2 * .pi - (.pi / 2)
                    let bx = center.x + radius * cos(angle)
                    let by = center.y + radius * sin(angle)

                    ZStack {
                        // Bead Glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        colors.bright.opacity(0.65),
                                        colors.bright.opacity(0.18),
                                        Color.clear
                                    ]),
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: size * 0.11
                                )
                            )
                            .frame(width: size * 0.22, height: size * 0.22)
                            .scaleEffect(breathPhase ? 1.08 : 0.94)

                        // Bead Core
                        Circle()
                            .fill(colors.bright)
                            .frame(width: size * 0.085, height: size * 0.085)

                        // White Eye
                        Circle()
                            .fill(Color.white)
                            .frame(width: size * 0.035, height: size * 0.035)
                    }
                    .position(x: bx, y: by)
                }
            }

            // Center Display
            VStack(spacing: 4) {
                if isWord {
                    Text(centerTitle)
                        .font(HeliTypography.countdownWord(28))
                        .foregroundColor(tone == .now || tone == .started ? HeliColors.highlightGold : .white)
                        .tracking(-0.5)
                } else if isHours {
                    Text(centerTitle)
                        .font(HeliTypography.hoursNum(32))
                        .foregroundColor(.white)
                        .tracking(-0.5)
                } else {
                    Text(centerTitle)
                        .font(HeliTypography.countdownNum(centerTitle.count >= 3 ? 46 : 54))
                        .foregroundColor(.white)
                        .tracking(-1.5)
                }

                if !centerUnit.isEmpty {
                    Text(centerUnit.uppercased())
                        .font(HeliTypography.dialUnit(9))
                        .foregroundColor(Color.white.opacity(0.78))
                        .tracking(1.4)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(.center)
            // Keep the label inside the ring and clear of the hour ticks.
            .frame(width: 116)
        }
        .frame(width: 168, height: 168)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                breathPhase = true
            }
        }
    }
}
