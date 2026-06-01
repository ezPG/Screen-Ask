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
    private var currentScreenshotURLs: [URL] = []
    private var latestImages: [URL: NSImage] = [:]
    private var scopedWatchFolderURL: URL?
    private var lastHandledScreenshotPath: String?
    private var lastHandledScreenshotAt: Date = .distantPast
    private var openURLObserver: NSObjectProtocol?
    private var becameActiveObserver: NSObjectProtocol?
    private var suppressedMiniTriggerPath: String?
    private var suppressedMiniTriggerUntil: Date = .distantPast
    private var miniTriggerCooldownByPath: [String: Date] = [:]
    private var chatHistory: [MessageBuilder.ChatTurn] = []
    private var streamingAssistantBuffer: String = ""
    private var activeScopedFolders: [URL] = []

    init() {
        PermissionManager.ensureRequiredPermissions()

        hudController.onAsk = { [weak self] prompt in
            self?.askAI(prompt: prompt)
        }
        hudController.onRemoveImage = { [weak self] url in
            self?.removeImageFromContext(url)
        }
        hudController.onDeleteImage = { [weak self] url in
            self?.deleteImage(url)
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
        for folder in activeScopedFolders {
            folder.stopAccessingSecurityScopedResource()
        }
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

        currentScreenshotURLs = [url]
        latestScreenshotPath = url.path
        canShowHUDForLatestScreenshot = true

        // If HUD is already open, do not show mini trigger for incoming filesystem noise.
        if hudController.isVisible {
            statusMessage = "HUD already visible; suppressing mini trigger"
            return
        }

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
        // Prevent repeat mini trigger from duplicate/secondary writes for the same file.
        miniTriggerCooldownByPath[url.path] = Date().addingTimeInterval(settings.autoDismissSeconds + 3)
        statusMessage = "Mini ask trigger shown"

        Task { @MainActor in
            guard let image = await loadImageWhenReady(from: url) else {
                statusMessage = "Image not ready yet. Mini trigger is available."
                return
            }
            latestImages[url] = image
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
                if isPermissionError(error),
                   await requestFolderAccessForFile(url, purpose: "read this image") {
                    continue
                }
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
            let targetURL = currentScreenshotURLs.first ?? latestImageInWatchFolder()
            guard let screenshotURL = targetURL else {
                statusMessage = "No screenshot available yet"
                return
            }

            let previousURLs = currentScreenshotURLs
            currentScreenshotURLs = [screenshotURL]
            latestScreenshotPath = screenshotURL.path

            if latestImages[screenshotURL] == nil || previousURLs != currentScreenshotURLs {
                if let loaded = await loadImageWhenReady(from: screenshotURL) {
                    latestImages[screenshotURL] = loaded
                }
            }

            guard latestImages[screenshotURL] != nil else {
                statusMessage = "Could not load screenshot image for HUD from \(screenshotURL.lastPathComponent)"
                return
            }

            miniTriggerController.dismiss()
            hudController.show(
                images: latestImages,
                contextURLs: currentScreenshotURLs,
                autoDismiss: settings.autoDismissSeconds,
                position: settings.hudPosition
            )
            // Prevent immediate re-show of mini trigger for the same file after HUD opens.
            miniTriggerCooldownByPath[screenshotURL.path] = Date().addingTimeInterval(settings.autoDismissSeconds + 3)
            chatHistory.removeAll()
            statusMessage = "HUD shown"
        }
    }

    private func consumePendingQuickActionRequest() {
        guard let paths = QuickActionRequestStore.readAndConsumeRequest() else { return }
        let fileURLs = paths.map { URL(fileURLWithPath: $0) }
        openImagesFromExternalTrigger(fileURLs)
    }

    private func openImagesFromExternalTrigger(_ fileURLs: [URL]) {
        let validURLs = fileURLs.filter { isSupportedImageFile($0) }
        guard !validURLs.isEmpty else {
            statusMessage = "Unsupported file types"
            return
        }

        Task { @MainActor in
            currentScreenshotURLs = validURLs
            latestScreenshotPath = validURLs.first?.path ?? ""
            canShowHUDForLatestScreenshot = true

            for url in validURLs {
                suppressedMiniTriggerPath = url.path
                suppressedMiniTriggerUntil = Date().addingTimeInterval(6)
                if let image = await loadImageWhenReady(from: url) {
                    latestImages[url] = image
                }
            }

            miniTriggerController.dismiss()
            hudController.show(
                images: latestImages,
                contextURLs: currentScreenshotURLs,
                autoDismiss: nil,
                position: settings.hudPosition
            )
            chatHistory.removeAll()
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
        openImagesFromExternalTrigger([fileURL])
    }

    private func removeImageFromContext(_ url: URL) {
        currentScreenshotURLs.removeAll { $0 == url }
        latestImages.removeValue(forKey: url)
        hudController.removeImage(for: url)
        if currentScreenshotURLs.isEmpty {
            hudController.dismiss()
        } else {
            hudController.setContextURLs(currentScreenshotURLs)
        }
    }

    private func deleteImage(_ url: URL) {
        do {
            var trashed: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
            removeImageFromContext(url)
            statusMessage = "Moved image to Trash"
        } catch {
            if isPermissionError(error),
               requestFolderAccessForFileSync(url, purpose: "delete this image") {
                do {
                    var trashed: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
                    removeImageFromContext(url)
                    statusMessage = "Moved image to Trash"
                    return
                } catch {
                    statusMessage = "Delete failed after permission grant: \(error.localizedDescription)"
                }
            } else {
                statusMessage = "Delete failed: \(error.localizedDescription)"
            }
        }
    }

    private func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == 257
    }

    private func requestFolderAccessForFileSync(_ fileURL: URL, purpose: String) -> Bool {
        if let scopedURL = FolderAccessManager.startAccessingIfGranted(for: fileURL) {
            activeScopedFolders.append(scopedURL)
            return true
        }

        let parent = fileURL.deletingLastPathComponent()
        guard let granted = FolderAccessManager.chooseAccessForFolder(
            startingAt: parent,
            message: "ScreenAsk needs access to \(parent.lastPathComponent) to \(purpose)."
        ) else {
            return false
        }
        guard granted.startAccessingSecurityScopedResource() else { return false }
        activeScopedFolders.append(granted)
        let grantedPath = granted.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        return filePath.hasPrefix(grantedPath)
    }

    private func requestFolderAccessForFile(_ fileURL: URL, purpose: String) async -> Bool {
        await MainActor.run {
            requestFolderAccessForFileSync(fileURL, purpose: purpose)
        }
    }

    func askAI(prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        // Mark user interaction before any async work so auto-dismiss cannot close HUD mid-typing/send.
        hudController.setLoading(true)

        guard !settings.apiKey.isEmpty else {
            hudController.beginResponse(for: trimmedPrompt)
            hudController.appendResponse("Error: Missing Groq API key. Add it in Preferences.")
            hudController.setLoading(false)
            return
        }
        guard !currentScreenshotURLs.isEmpty else {
            hudController.setLoading(false)
            return
        }

        chatHistory.append(.init(role: "user", text: trimmedPrompt))
        hudController.beginResponse(for: trimmedPrompt)
        streamingAssistantBuffer = ""

        Task {
            defer {
                Task { @MainActor in
                    self.hudController.setLoading(false)
                }
            }

            // Route through tools (web search / scrape) if enabled.
            let routed = await ToolRouter.route(
                prompt: trimmedPrompt,
                history: chatHistory,
                webSearchEnabled: settings.webSearchEnabled,
                imageSearchEnabled: settings.imageSearchEnabled,
                apiKey: settings.apiKey,
                model: settings.selectedModel,
                groqClient: groqClient
            )

            // Show a tool usage indicator in the chat if a tool was invoked.
            if let toolUsed = routed.toolUsed {
                await MainActor.run {
                    self.hudController.appendResponse("🔍 \(toolUsed)\n\n")
                }
            }

            let effectivePrompt = routed.enrichedPrompt

            do {
                try await groqClient.streamVisionResponse(
                    apiKey: settings.apiKey,
                    model: settings.selectedModel,
                    systemPrompt: settings.customSystemPrompt,
                    history: chatHistory,
                    prompt: effectivePrompt,
                    imageFileURLs: currentScreenshotURLs
                ) { [weak self] delta in
                    await MainActor.run {
                        self?.streamingAssistantBuffer += delta
                        self?.hudController.appendResponse(delta)
                    }
                }

                await MainActor.run {
                    let trimmed = self.streamingAssistantBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        self.chatHistory.append(.init(role: "assistant", text: trimmed))
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
                    let errorText = "Error: \(message)"
                    self.hudController.appendResponse("\n\n\(errorText)")
                    self.chatHistory.append(.init(role: "assistant", text: errorText))
                }
            }
        }
    }
}
