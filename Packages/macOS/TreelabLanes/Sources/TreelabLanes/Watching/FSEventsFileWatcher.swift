import CoreServices
public import Foundation

/// Watches folders with FSEvents: one stream for many paths, woken by the system only when a
/// file changes, never by a timer. Used for documents lanes edit in place (batch files), which a
/// folder watch cannot see.
public struct FSEventsFileWatcher: FileEventWatching {
    private let latency: TimeInterval

    /// Creates a watcher.
    /// - Parameter latency: how long FSEvents groups changes before delivering them, 0.3 s by default.
    public init(latency: TimeInterval = 0.3) {
        self.latency = latency
    }

    /// Watches `paths` until the stream is dropped.
    /// - Parameter paths: absolute paths; missing ones are watched from their nearest existing parent by FSEvents.
    /// - Returns: batches of changed paths.
    public func changes(under paths: [String]) -> AsyncStream<[String]> {
        AsyncStream { continuation in
            guard !paths.isEmpty else { continuation.finish(); return }
            let box = FSEventsContinuationBox(continuation: continuation)
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passRetained(box).toOpaque(),
                retain: nil,
                release: { info in
                    guard let info else { return }
                    Unmanaged<FSEventsContinuationBox>.fromOpaque(info).release()
                },
                copyDescription: nil
            )
            // @convention(c) trampoline FSEvents requires; it only forwards the paths.
            let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
                guard let info else { return }
                let box = Unmanaged<FSEventsContinuationBox>.fromOpaque(info).takeUnretainedValue()
                let array = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
                box.continuation.yield(array.prefix(count).compactMap { $0 as? String })
            }
            let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault, callback, &context, paths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
            ) else {
                continuation.finish()
                return
            }
            let queue = DispatchQueue(label: "sh.treelab.lanes.fsevents")
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            let handle = FSEventsStreamHandle(stream: stream, queue: queue)
            continuation.onTermination = { _ in handle.stop() }
        }
    }
}

/// Holds the continuation for the C callback.
private final class FSEventsContinuationBox: Sendable {
    let continuation: AsyncStream<[String]>.Continuation
    init(continuation: AsyncStream<[String]>.Continuation) { self.continuation = continuation }
}

/// Owns the FSEvents stream until the AsyncStream ends.
private final class FSEventsStreamHandle: Sendable {
    // FSEventStreamRef is a C pointer, not Sendable; it is only touched once, in stop(),
    // after the stream was started, from the termination handler.
    nonisolated(unsafe) let stream: FSEventStreamRef
    let queue: DispatchQueue
    init(stream: FSEventStreamRef, queue: DispatchQueue) {
        self.stream = stream
        self.queue = queue
    }
    func stop() {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
