import AppKit
import Combine
import Foundation
import SwiftUI

enum HUDPosition: String, CaseIterable, Identifiable {
    case bottomRight
    case bottomLeft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottomRight: return "Bottom Right"
        case .bottomLeft: return "Bottom Left"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("selectedModel") var selectedModel: String = "llama-3.2-11b-vision-preview"
    @AppStorage("watchFolderPath") var watchFolderPath: String = NSString(string: "~/Desktop").expandingTildeInPath
    @AppStorage("hudPosition") private var hudPositionRaw: String = HUDPosition.bottomRight.rawValue
    @AppStorage("autoDismissSeconds") var autoDismissSeconds: Double = 8

    @Published var apiKey: String = KeychainManager.loadAPIKey()

    var hudPosition: HUDPosition {
        get { HUDPosition(rawValue: hudPositionRaw) ?? .bottomRight }
        set { hudPositionRaw = newValue.rawValue }
    }

    func saveAPIKey() {
        do {
            try KeychainManager.saveAPIKey(apiKey)
        } catch {
            print("Failed to save API key: \(error)")
        }
    }

    func requestWatchFolderAccess() -> Bool {
        guard let selectedURL = FolderAccessManager.chooseWatchFolder(currentPath: watchFolderPath) else {
            return false
        }
        watchFolderPath = selectedURL.path
        return true
    }
}
