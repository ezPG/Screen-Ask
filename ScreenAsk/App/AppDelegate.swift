import AppKit
import Foundation

extension Notification.Name {
    static let screenAskDidOpenURL = Notification.Name("screenAskDidOpenURL")
}

final class ScreenAskAppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            self.configureSettingsWindow(window)
        }
    }

    deinit {
        if let settingsWindowObserver {
            NotificationCenter.default.removeObserver(settingsWindowObserver)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NotificationCenter.default.post(name: .screenAskDidOpenURL, object: url)
        }
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        // SwiftUI settings window can reopen on a previously used Space.
        // This behavior keeps it on the active Space when opened from the menubar app.
        guard window.title.localizedCaseInsensitiveContains("settings") else { return }
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
    }
}
