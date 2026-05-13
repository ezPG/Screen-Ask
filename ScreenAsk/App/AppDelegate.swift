import AppKit
import Foundation

extension Notification.Name {
    static let screenAskDidOpenURL = Notification.Name("screenAskDidOpenURL")
}

final class ScreenAskAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NotificationCenter.default.post(name: .screenAskDidOpenURL, object: url)
        }
    }
}
