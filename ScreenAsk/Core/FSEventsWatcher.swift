import CoreServices
import Foundation

final class FSEventsWatcher {
    private var streamRef: FSEventStreamRef?
    private let folderURL: URL
    private let onFileDetected: (URL, FSEventStreamEventFlags) -> Void

    init(folderURL: URL, onFileDetected: @escaping (URL, FSEventStreamEventFlags) -> Void) {
        self.folderURL = folderURL
        self.onFileDetected = onFileDetected
    }

    deinit {
        stop()
    }

    func start() {
        stop()

        let callback: FSEventStreamCallback = { _, context, count, pathsPointer, eventFlagsPointer, _ in
            guard let context else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(context).takeUnretainedValue()
            let paths = unsafeBitCast(pathsPointer, to: NSArray.self) as? [String] ?? []
            watcher.handle(paths: paths, flags: eventFlagsPointer, count: count)
        }

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [folderURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let streamRef else { return }
        FSEventStreamScheduleWithRunLoop(streamRef, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(streamRef)
    }

    func stop() {
        guard let streamRef else { return }
        FSEventStreamStop(streamRef)
        FSEventStreamInvalidate(streamRef)
        FSEventStreamRelease(streamRef)
        self.streamRef = nil
    }

    private func handle(paths: [String], flags: UnsafePointer<FSEventStreamEventFlags>?, count: Int) {
        guard count > 0 else { return }

        for index in 0..<count {
            guard index < paths.count else { break }
            let path = paths[index]
            let url = URL(fileURLWithPath: path)
            guard url.pathExtension.lowercased() == "png" else { continue }

            let eventFlags = flags?[index] ?? 0
            guard shouldTriggerFor(url: url, eventFlags: eventFlags) else { continue }
            onFileDetected(url, eventFlags)
        }
    }

    private func shouldTriggerFor(url: URL, eventFlags: FSEventStreamEventFlags) -> Bool {
        let removed = UInt32(kFSEventStreamEventFlagItemRemoved)
        let movedOut = UInt32(kFSEventStreamEventFlagItemRenamed)

        if (eventFlags & removed) != 0 {
            return false
        }

        // For renamed events, trigger only if the file still exists (rename-in/write completion).
        if (eventFlags & movedOut) != 0 {
            return FileManager.default.fileExists(atPath: url.path)
        }

        let created = UInt32(kFSEventStreamEventFlagItemCreated)
        let modified = UInt32(kFSEventStreamEventFlagItemModified)
        let inodeMeta = UInt32(kFSEventStreamEventFlagItemInodeMetaMod)

        return (eventFlags & created) != 0 ||
            (eventFlags & modified) != 0 ||
            (eventFlags & inodeMeta) != 0
    }
}
