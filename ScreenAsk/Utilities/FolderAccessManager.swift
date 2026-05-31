import AppKit
import Foundation

enum FolderAccessManager {
    private static let bookmarkKey = "watchFolderBookmarkData"
    private static let grantedFolderBookmarksKey = "grantedFolderBookmarksDataByPath"

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

    static func chooseAccessForFolder(startingAt folderURL: URL, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Grant Access"
        panel.message = message
        panel.directoryURL = folderURL

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return nil
        }

        saveGrantedFolderBookmark(for: selectedURL)
        return selectedURL
    }

    static func startAccessingIfGranted(for fileURL: URL) -> URL? {
        let folderURL = fileURL.deletingLastPathComponent()
        guard let bookmarkDataByPath = UserDefaults.standard.dictionary(forKey: grantedFolderBookmarksKey) as? [String: Data],
              let data = bookmarkDataByPath[folderURL.standardizedFileURL.path] else {
            return nil
        }

        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if isStale {
            saveGrantedFolderBookmark(for: resolvedURL)
        }

        guard resolvedURL.startAccessingSecurityScopedResource() else {
            return nil
        }
        return resolvedURL
    }

    static func saveGrantedFolderBookmark(for folderURL: URL) {
        guard let data = try? folderURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }
        var stored = (UserDefaults.standard.dictionary(forKey: grantedFolderBookmarksKey) as? [String: Data]) ?? [:]
        stored[folderURL.standardizedFileURL.path] = data
        UserDefaults.standard.set(stored, forKey: grantedFolderBookmarksKey)
    }
}
