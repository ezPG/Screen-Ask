import AppKit
import Combine
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var latestScreenshotPath: String = "No screenshot detected yet"
    @Published var canShowHUDForLatestScreenshot: Bool = false
    @Published var statusMessage: String = "Idle"

    let settings = AppSettings()

    private let groqClient = GroqClient()
    private let hudController = FloatingHUDController()
    private let responseController = ResponsePanelController()
    private var watcher: FSEventsWatcher?
    private var currentScreenshotURL: URL?
    private var latestImage: NSImage?
    private var scopedWatchFolderURL: URL?
    private var lastHandledScreenshotPath: String?
    private var lastHandledScreenshotAt: Date = .distantPast

    init() {
        PermissionManager.ensureRequiredPermissions()

        hudController.onAsk = { [weak self] prompt in
            self?.askAI(prompt: prompt)
        }

        startWatcher()
    }

    deinit {
        scopedWatchFolderURL?.stopAccessingSecurityScopedResource()
    }

    func restartWatcher() {
        startWatcher()
    }

    private func startWatcher() {
        watcher?.stop()

        if let scopedWatchFolderURL {
            scopedWatchFolderURL.stopAccessingSecurityScopedResource()
            self.scopedWatchFolderURL = nil
        }

        let folderURL = URL(fileURLWithPath: settings.watchFolderPath)

        if let bookmarkedURL = FolderAccessManager.resolveBookmarkURL(),
           bookmarkedURL.standardizedFileURL.path == folderURL.standardizedFileURL.path {
            if bookmarkedURL.startAccessingSecurityScopedResource() {
                scopedWatchFolderURL = bookmarkedURL
                statusMessage = "Watching \(folderURL.path) (granted access)"
            } else {
                statusMessage = "Watching \(folderURL.path) (bookmark access failed)"
            }
        } else {
            statusMessage = "Watching \(folderURL.path) (no explicit access grant)"
        }

        watcher = FSEventsWatcher(folderURL: folderURL) { [weak self] url in
            Task { @MainActor in
                self?.handleScreenshot(url)
            }
        }
        watcher?.start()
    }

    private func handleScreenshot(_ url: URL) {
        let now = Date()
        if lastHandledScreenshotPath == url.path,
           now.timeIntervalSince(lastHandledScreenshotAt) < 3 {
            statusMessage = "Ignoring duplicate screenshot event"
            return
        }

        lastHandledScreenshotPath = url.path
        lastHandledScreenshotAt = now

        currentScreenshotURL = url
        latestScreenshotPath = url.path
        canShowHUDForLatestScreenshot = true
        statusMessage = "Detected screenshot: \(url.lastPathComponent)"

        Task { @MainActor in
            guard let image = await loadImageWhenReady(from: url) else {
                statusMessage = "Image not ready yet. Use 'Show HUD For Latest Screenshot'."
                return
            }
            latestImage = image

            try? await Task.sleep(nanoseconds: 300_000_000)
            if hudController.shouldSuppressAutoShow {
                statusMessage = "New screenshot detected while typing; HUD not interrupted"
                return
            }

            hudController.show(
                image: image,
                autoDismiss: settings.autoDismissSeconds,
                position: settings.hudPosition
            )
            statusMessage = "HUD shown"
        }
    }

    private func loadImageWhenReady(from url: URL) async -> NSImage? {
        for attempt in 0..<12 {
            do {
                let data = try Data(contentsOf: url)
                if let image = NSImage(data: data), image.isValid {
                    return image
                }
                statusMessage = "Image decode failed (attempt \(attempt + 1)/12)"
            } catch {
                // Cocoa error 257 usually means privacy permission denied for Desktop/Documents.
                statusMessage = "Read failed: \(error.localizedDescription)"
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return nil
    }

    private func latestPNGInWatchFolder() -> URL? {
        let folderURL = URL(fileURLWithPath: settings.watchFolderPath)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        var latestURL: URL?
        var latestDate = Date.distantPast

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "png" else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let modified = values.contentModificationDate ?? .distantPast
            if modified > latestDate {
                latestDate = modified
                latestURL = fileURL
            }
        }

        return latestURL
    }

    func showHUDForLatestScreenshot() {
        Task { @MainActor in
            let targetURL = currentScreenshotURL ?? latestPNGInWatchFolder()
            guard let screenshotURL = targetURL else {
                statusMessage = "No screenshot available yet"
                return
            }

            let previousURL = currentScreenshotURL
            currentScreenshotURL = screenshotURL
            latestScreenshotPath = screenshotURL.path

            if latestImage == nil || previousURL != screenshotURL {
                latestImage = await loadImageWhenReady(from: screenshotURL)
            }

            guard let image = latestImage else {
                statusMessage = "Could not load screenshot image for HUD from \(screenshotURL.lastPathComponent)"
                return
            }

            hudController.show(
                image: image,
                autoDismiss: settings.autoDismissSeconds,
                position: settings.hudPosition
            )
            statusMessage = "HUD shown from menu action"
        }
    }

    func askAI(prompt: String) {
        guard !settings.apiKey.isEmpty else {
            responseController.reset()
            responseController.append("Missing Groq API key. Add it in Preferences.")
            responseController.show()
            return
        }
        guard let screenshotURL = currentScreenshotURL else { return }

        hudController.setLoading(true)
        responseController.reset()
        responseController.show()

        Task {
            defer {
                Task { @MainActor in
                    self.hudController.setLoading(false)
                }
            }

            do {
                try await groqClient.streamVisionResponse(
                    apiKey: settings.apiKey,
                    model: settings.selectedModel,
                    prompt: prompt,
                    imageFileURL: screenshotURL
                ) { [weak self] delta in
                    await MainActor.run {
                        self?.responseController.append(delta)
                    }
                }
            } catch {
                let message: String
                if let urlError = error as? URLError, urlError.code == .cannotFindHost {
                    message = "Could not resolve api.groq.com. Check DNS/network/VPN and try again."
                } else if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
                    message = "No internet connection. Connect to network and retry."
                } else {
                    message = error.localizedDescription
                }

                await MainActor.run {
                    self.responseController.append("\n\nError: \(message)")
                }
            }
        }
    }
}
