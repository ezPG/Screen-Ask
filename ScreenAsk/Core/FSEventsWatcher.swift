import CoreServices
import Foundation

final class FSEventsWatcher {
    private var streamRef: FSEventStreamRef?
    private let folderURL: URL
    private let onFileDetected: (URL) -> Void

    init(folderURL: URL, onFileDetected: @escaping (URL) -> Void) {
        self.folderURL = folderURL
        self.onFileDetected = onFileDetected
    }

    deinit {
        stop()
    }

    func start() {
        stop()

        let callback: FSEventStreamCallback = { _, context, count, pathsPointer, _, _ in
            guard let context else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(context).takeUnretainedValue()
            let paths = unsafeBitCast(pathsPointer, to: NSArray.self) as? [String] ?? []
            watcher.handle(paths: paths, count: count)
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

    private func handle(paths: [String], count: Int) {
        guard count > 0 else { return }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard url.pathExtension.lowercased() == "png" else { continue }
            onFileDetected(url)
        }
    }
}
