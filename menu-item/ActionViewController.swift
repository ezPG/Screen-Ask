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
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem], !inputItems.isEmpty else {
            complete()
            return
        }

        var urls: [URL] = []
        let group = DispatchGroup()

        for item in inputItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        if let fileURL = item as? URL {
                            DispatchQueue.main.async { urls.append(fileURL) }
                        }
                        group.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                        if let fileURL = item as? URL {
                            DispatchQueue.main.async { urls.append(fileURL) }
                        }
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) {
            if urls.isEmpty {
                self.complete()
            } else {
                self.persistAndOpenHostApp(fileURLs: urls)
            }
        }
    }

    private func persistAndOpenHostApp(fileURLs: [URL]) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            complete()
            return
        }

        let sharedPaths = fileURLs.map { $0.resolvingSymlinksInPath().path }

        if sharedPaths.isEmpty {
            complete()
            return
        }

        // We use a new key for array to avoid conflict with old single string key
        defaults.set(sharedPaths, forKey: "quick_action_image_paths")
        defaults.synchronize()

        if let wakeURL = URL(string: "screenask://ask") {
            NSWorkspace.shared.open(wakeURL)
        }

        complete()
    }

    private func complete() {
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
