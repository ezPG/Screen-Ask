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
    private let miniTriggerController = MiniTriggerPanelController()
    private var watcher: FSEventsWatcher?
    private var currentScreenshotURL: URL?
    private var latestImage: NSImage?
    private var scopedWatchFolderURL: URL?
    private var lastHandledScreenshotPath: String?
    private var lastHandledScreenshotAt: Date = .distantPast
    private var openURLObserver: NSObjectProtocol?
    private var becameActiveObserver: NSObjectProtocol?
    private var suppressedMiniTriggerPath: String?
    private var suppressedMiniTriggerUntil: Date = .distantPast
    private var miniTriggerCooldownByPath: [String: Date] = [:]

    init() {
        PermissionManager.ensureRequiredPermissions()

        hudController.onAsk = { [weak self] prompt in
            self?.askAI(prompt: prompt)
        }

        miniTriggerController.onAskTapped = { [weak self] in
            self?.showHUDForLatestScreenshot()
        }

        openURLObserver = NotificationCenter.default.addObserver(
            forName: .screenAskDidOpenURL,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let url = note.object as? URL else { return }
            self?.handleIncomingURL(url)
        }

        becameActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.consumePendingQuickActionRequest()
        }

        startWatcher()
        consumePendingQuickActionRequest()
    }

    deinit {
        if let openURLObserver {
            NotificationCenter.default.removeObserver(openURLObserver)
        }
        if let becameActiveObserver {
            NotificationCenter.default.removeObserver(becameActiveObserver)
        }
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

        watcher = FSEventsWatcher(folderURL: folderURL) { [weak self] url, _ in
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

        if suppressedMiniTriggerPath == url.path, Date() <= suppressedMiniTriggerUntil {
            statusMessage = "Skipping mini trigger for quick action image"
            return
        }

        if let until = miniTriggerCooldownByPath[url.path], Date() <= until {
            statusMessage = "Ignoring repeat event for same screenshot"
            return
        }

        if hudController.shouldSuppressAutoShow {
            statusMessage = "New screenshot detected while typing; HUD not interrupted"
            return
        }

        miniTriggerController.show(
            autoDismiss: settings.autoDismissSeconds,
            position: settings.hudPosition
        )
        miniTriggerCooldownByPath[url.path] = Date().addingTimeInterval(settings.autoDismissSeconds + 3)
        statusMessage = "Mini ask trigger shown"

        Task { @MainActor in
            guard let image = await loadImageWhenReady(from: url) else {
                statusMessage = "Image not ready yet. Mini trigger is available."
                return
            }
            latestImage = image
            statusMessage = "Screenshot ready"
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

    private func latestImageInWatchFolder() -> URL? {
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
            guard isSupportedImageFile(fileURL) else { continue }
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

    private func isSupportedImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "webp", "heic", "heif", "gif", "bmp", "tiff"].contains(ext)
    }

    func showHUDForLatestScreenshot() {
        Task { @MainActor in
            let targetURL = currentScreenshotURL ?? latestImageInWatchFolder()
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

            miniTriggerController.dismiss()
            hudController.show(
                image: image,
                autoDismiss: settings.autoDismissSeconds,
                position: settings.hudPosition
            )
            statusMessage = "HUD shown"
        }
    }

    private func consumePendingQuickActionRequest() {
        guard let path = QuickActionRequestStore.readAndConsumeRequest() else { return }
        let fileURL = URL(fileURLWithPath: path)
        openImageFromExternalTrigger(fileURL)
    }

    private func openImageFromExternalTrigger(_ fileURL: URL) {
        guard isSupportedImageFile(fileURL) else {
            statusMessage = "Unsupported file type: \(fileURL.pathExtension)"
            return
        }

        Task { @MainActor in
            currentScreenshotURL = fileURL
            latestScreenshotPath = fileURL.path
            canShowHUDForLatestScreenshot = true

            suppressedMiniTriggerPath = fileURL.path
            suppressedMiniTriggerUntil = Date().addingTimeInterval(6)

            latestImage = await loadImageWhenReady(from: fileURL)
            guard let image = latestImage else {
                statusMessage = "Could not load image from external trigger"
                return
            }

            miniTriggerController.dismiss()
            hudController.show(
                image: image,
                autoDismiss: nil,
                position: settings.hudPosition
            )
            statusMessage = "Opened HUD from quick action"
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "screenask" else { return }
        guard url.host?.lowercased() == "ask" else { return }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let fileValue = components.queryItems?.first(where: { $0.name == "file" })?.value,
              let decoded = fileValue.removingPercentEncoding else {
            statusMessage = "Invalid quick action URL"
            return
        }

        let fileURL = URL(fileURLWithPath: decoded)
        openImageFromExternalTrigger(fileURL)
    }

    func askAI(prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        guard !settings.apiKey.isEmpty else {
            hudController.beginResponse()
            hudController.appendResponse("Missing Groq API key. Add it in Preferences.")
            return
        }
        guard let screenshotURL = currentScreenshotURL else { return }

        hudController.beginResponse()
        hudController.setLoading(true)

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
                    prompt: trimmedPrompt,
                    imageFileURL: screenshotURL
                ) { [weak self] delta in
                    await MainActor.run {
                        self?.hudController.appendResponse(delta)
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
                    self.hudController.appendResponse("\n\nError: \(message)")
                }
            }
        }
    }
}
