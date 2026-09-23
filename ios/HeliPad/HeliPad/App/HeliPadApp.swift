import SwiftUI
import UserNotifications

@main
struct HeliPadApp: App {
    @UIApplicationDelegateAdaptor(HeliPadAppDelegate.self) private var appDelegate

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

/// Exists for one job: the notification delegate has to be in place before
/// launch finishes. A "Mark done" tapped on the lock screen wakes the app in
/// the background with no scene, so a delegate installed from a view's
/// `onAppear` would never see it.
final class HeliPadAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let responder = NotificationResponder.shared
        responder.handler = { action in
            await AppStore.shared.handleNotificationAction(action)
        }
        UNUserNotificationCenter.current().delegate = responder
        NotificationService.shared.registerCategories()
        return true
    }
}
