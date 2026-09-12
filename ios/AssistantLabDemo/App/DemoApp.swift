import SwiftUI

/// A harness app for the assistant work stream.
///
/// This is not HeliPad. It exists so the chat sheet can be seen and used on a
/// real device without touching the app target, and it will be deleted once
/// A06 is integrated.
///
/// It links `AssistantKit`, `AssistantMocks` and `AssistantUI` only. In
/// particular it does NOT link `AssistantDevRelay`, so there is still no build
/// anywhere that puts a provider key in an app bundle. The chat is answered by
/// the deterministic scripted planner; the live model is exercised from the
/// command line instead.
@main
struct AssistantLabDemoApp: App {
    var body: some Scene {
        WindowGroup {
            DemoHomeView()
        }
    }
}
