import SwiftUI
import ListsUI

@main
struct ListsPreviewApp: App {
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "--server"), arguments.indices.contains(i + 1) {
            UserDefaults.standard.set(arguments[i + 1], forKey: "lists-preview-service")
        }
    }
    var body: some Scene { WindowGroup { ListsPreviewView() } }
}
