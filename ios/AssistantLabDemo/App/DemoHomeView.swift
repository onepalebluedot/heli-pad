import SwiftUI
import AssistantKit
import AssistantMocks
import AssistantUI

/// A blank page with the assistant launcher on it.
///
/// The launcher is drawn the way N01 describes it - a raised circular action
/// about 56 points across, carrying a speech bubble with a calendar
/// checkmark, in the existing forest-green palette - so the icon can be judged
/// here before the real navigation bar is built.
struct DemoHomeView: View {
    /// Which model answers. Rebuilding the view model is the whole switch, so
    /// the two paths cannot accidentally share state.
    enum Backend: String, CaseIterable, Identifiable {
        case scripted
        case liveRelay

        var id: String { rawValue }
        var label: String { self == .scripted ? "Scripted" : "Live relay" }
    }

    @State private var backend: Backend = .scripted
    @State private var model: AssistantChatModel
    @State private var showsAssistant = false
    /// Set when an event link is tapped, standing in for the app routing to
    /// that event's week.
    @State private var lastOpenedEvent: String?
    @State private var relayReachable: Bool?

    /// Where the local relay listens. See tools/dev-relay/relay.py.
    private static let relayURL = URL(string: "http://localhost:8787")!
    /// Not a secret: it identifies the development session to the local relay.
    /// The provider key lives in the relay process and never reaches the app,
    /// which is the A01 arrangement this is standing in for.
    private static let devSessionToken = "dev-local-token"

    init() {
        _model = State(initialValue: Self.makeModel(.scripted))
    }

    private static func makeModel(_ backend: Backend) -> AssistantChatModel {
        let household = Fixtures.household()
        let session = Fixtures.session
        let proposals = ProposalStore(query: household, command: household)
        let configuration = AssistantConfiguration(relayBaseURL: relayURL)

        let client: LunaClient = switch backend {
        case .scripted:
            ScriptedLunaClient()
        case .liveRelay:
            // The production client, unchanged. Only its destination is local.
            RelayLunaClient(
                configuration: configuration,
                tokens: StaticTokenProvider(devSessionToken)
            )
        }

        let engine = AssistantEngine(
            client: client,
            router: ToolRouter(query: household),
            proposals: proposals,
            query: household,
            configuration: configuration
        )
        return AssistantChatModel(
            engine: engine,
            transcript: ChatTranscript(),
            session: session,
            hasSeenDataDisclosure: true
        )
    }

    private func checkRelay() async {
        var request = URLRequest(url: Self.relayURL.appendingPathComponent("health"))
        request.timeoutInterval = 3
        let reachable = (try? await URLSession.shared.data(for: request))
            .map { ($0.1 as? HTTPURLResponse)?.statusCode == 200 } ?? false
        relayReachable = reachable
    }

    var body: some View {
        ZStack {
            HeliDemoColors.canvasIvory.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 10) {
                    Text("Assistant harness")
                        .font(.system(size: 26, weight: .medium, design: .serif))
                        .foregroundStyle(HeliDemoColors.forestGreen)
                    Text("Blank page. The button opens the assistant sheet.")
                        .font(.system(size: 13))
                        .foregroundStyle(HeliDemoColors.mutedGray)
                        .multilineTextAlignment(.center)
                    Text("Mock household \u{00B7} today is \(Fixtures.today)")
                        .font(.system(size: 11))
                        .foregroundStyle(HeliDemoColors.mutedGray.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Picker("Backend", selection: $backend) {
                    ForEach(Backend.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                .padding(.top, 22)
                .onChange(of: backend) { _, newValue in
                    // A fresh view model per backend: no transcript, pending
                    // review or engine context survives the switch.
                    model = Self.makeModel(newValue)
                    if newValue == .liveRelay {
                        Task { await checkRelay() }
                    } else {
                        relayReachable = nil
                    }
                }

                if backend == .liveRelay {
                    Text(relayStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(relayReachable == false ? HeliDemoColors.sunOchre : HeliDemoColors.mutedGray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 10)
                }

                if let event = lastOpenedEvent {
                    Text("Tapped event \(event) \u{2014} the app would open its week here.")
                        .font(.system(size: 11))
                        .foregroundStyle(HeliDemoColors.sunOchre)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 18)
                }

                Spacer()

                AssistantLauncherButton { showsAssistant = true }
                    .padding(.bottom, 34)
            }
        }
        .sheet(isPresented: $showsAssistant) {
            AssistantChatView(
                model: model,
                onOpenEvent: { eventID, _ in
                    lastOpenedEvent = eventID
                    showsAssistant = false
                },
                onDismiss: { showsAssistant = false }
            )
        }
    }
}

extension DemoHomeView {
    var relayStatus: String {
        switch relayReachable {
        case true: return "Relay reachable on localhost:8787 \u{00B7} the key stays in that process"
        case false: return "No relay on localhost:8787 \u{2014} run tools/dev-relay/relay.py"
        case nil: return "Checking for the local relay\u{2026}"
        }
    }
}

/// The centred launcher from product decision 6: a speech bubble containing a
/// compact calendar-and-checkmark motif, in the forest-green palette. Composed
/// from SF Symbols rather than drawn by hand, matching how the app's icon layer
/// works, and deliberately not a mascot or a provider logo.
struct AssistantLauncherButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(HeliDemoColors.cardWarmWhite)
                    .offset(y: -1)

                // The calendar-checkmark motif, sitting inside the bubble.
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(HeliDemoColors.forestGreen)
                    .offset(y: -3)
            }
        }
        // Press feedback comes from the button style, not a simultaneous drag
        // gesture. A DragGesture(minimumDistance: 0) alongside the button
        // swallows the tap outright - the press animation plays and the action
        // never fires.
        .buttonStyle(LauncherButtonStyle())
        .accessibilityLabel("Open HeliPad assistant")
    }
}

struct LauncherButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 56, height: 56)
            .background(
                Circle()
                    .fill(HeliDemoColors.forestGreen)
                    .shadow(
                        color: HeliDemoColors.forestGreen.opacity(0.28),
                        radius: configuration.isPressed ? 4 : 9,
                        y: configuration.isPressed ? 2 : 4
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

/// The handful of palette values the harness page itself needs. The sheet
/// carries its own copy of the full theme inside `AssistantUI`.
enum HeliDemoColors {
    static let canvasIvory = Color(red: 0xf6 / 255, green: 0xf4 / 255, blue: 0xed / 255)
    static let cardWarmWhite = Color(red: 0xff / 255, green: 0xfe / 255, blue: 0xf8 / 255)
    static let forestGreen = Color(red: 0x23 / 255, green: 0x57 / 255, blue: 0x46 / 255)
    static let mutedGray = Color(red: 0x68 / 255, green: 0x74 / 255, blue: 0x69 / 255)
    static let sunOchre = Color(red: 0xad / 255, green: 0x72 / 255, blue: 0x2d / 255)
}
