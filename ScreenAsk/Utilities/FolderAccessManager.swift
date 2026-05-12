import AppKit
import Foundation

enum FolderAccessManager {
    private static let bookmarkKey = "watchFolderBookmarkData"

    static func saveBookmark(for folderURL: URL) throws {
        let data = try folderURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    static func resolveBookmarkURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if isStale {
            try? saveBookmark(for: url)
        }

        return url
    }

    static func chooseWatchFolder(currentPath: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Grant Access"
        panel.message = "Choose your screenshot folder to grant ScreenAsk read access."
        panel.directoryURL = URL(fileURLWithPath: currentPath)

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return nil
        }

        try? saveBookmark(for: selectedURL)
        return selectedURL
    }
}
