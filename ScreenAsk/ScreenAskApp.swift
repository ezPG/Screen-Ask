import SwiftUI

@main
struct ScreenAskApp: App {
    @NSApplicationDelegateAdaptor(ScreenAskAppDelegate.self) var appDelegate
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("ScreenAsk", systemImage: "sparkles.rectangle.stack") {
            ContentView(coordinator: coordinator)
        }

        Settings {
            PreferencesView(settings: coordinator.settings)
                .onDisappear {
                    coordinator.restartWatcher()
                }
        }
    }
}
