import SwiftUI

@main
struct HeliPadApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Every colour in HeliColors is a fixed hex on a cream ground,
                // so there is no dark palette to switch to. Without this, system
                // controls (stepper labels, text fields, toggles) take their
                // dark-mode colours and vanish into the light surfaces.
                .preferredColorScheme(.light)
        }
    }
}
