import Cocoa
import UniformTypeIdentifiers

final class ActionViewController: NSViewController {
    private let appGroupID = "group.com.ezpg.screenask"
    private let requestKey = "quick_action_image_path"

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        processInputAndSendToHostApp()
    }

    private func processInputAndSendToHostApp() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments,
              !attachments.isEmpty else {
            complete()
            return
        }

        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                    guard let self else { return }
                    guard let fileURL = item as? URL else {
                        self.complete()
                        return
                    }
                    self.persistAndOpenHostApp(fileURL: fileURL)
                }
                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
                    guard let self else { return }
                    if let fileURL = item as? URL {
                        self.persistAndOpenHostApp(fileURL: fileURL)
                    } else {
                        self.complete()
                    }
                }
                return
            }
        }

        complete()
    }

    private func persistAndOpenHostApp(fileURL: URL) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            complete()
            return
        }

        guard let sharedURL = copyToSharedContainer(fileURL: fileURL) else {
            complete()
            return
        }

        defaults.set(sharedURL.path, forKey: requestKey)
        defaults.synchronize()

        if let wakeURL = URL(string: "screenask://ask") {
            NSWorkspace.shared.open(wakeURL)
        }

        complete()
    }

    private func copyToSharedContainer(fileURL: URL) -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return nil
        }

        let inputURL = fileURL.resolvingSymlinksInPath()
        let ext = inputURL.pathExtension.isEmpty ? "png" : inputURL.pathExtension
        let outputURL = containerURL
            .appendingPathComponent("incoming", isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            _ = inputURL.startAccessingSecurityScopedResource()
            defer { inputURL.stopAccessingSecurityScopedResource() }

            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
            return outputURL
        } catch {
            return nil
        }
    }

    private func complete() {
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
