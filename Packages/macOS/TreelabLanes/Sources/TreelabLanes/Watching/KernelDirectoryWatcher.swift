import Darwin
import Foundation

/// Watches the entries of folders, not their depth: a file or folder added, removed or renamed
/// directly inside. Used for `WATCH_ENTRIES=` (lab's lanes folder, a batch folder), so building
/// inside a lane never wakes Treelab.
public struct KernelDirectoryWatcher: FileEventWatching {
    /// Creates a watcher.
    public init() {}

    /// Watches the entries of `paths`.
    /// - Parameter paths: folders; missing ones are skipped.
    /// - Returns: the folder path each time its entries change.
    public func changes(under paths: [String]) -> AsyncStream<[String]> {
        AsyncStream { continuation in
            let queue = DispatchQueue(label: "sh.treelab.lanes.entries")
            // DispatchSource file-system sources have no async-native replacement (carve-out).
            let sources = Set(paths).compactMap { path -> (any DispatchSourceFileSystemObject)? in
                let descriptor = open(path, O_EVTONLY | O_DIRECTORY | O_CLOEXEC)
                guard descriptor >= 0 else { return nil }
                let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: queue)
                source.setEventHandler { continuation.yield([path]) }
                source.setCancelHandler { close(descriptor) }
                source.resume()
                return source
            }
            let holder = DirectorySourcesHolder(sources: sources)
            continuation.onTermination = { _ in holder.cancel() }
        }
    }
}

/// Keeps the folder sources alive until the stream ends.
private final class DirectorySourcesHolder: Sendable {
    let sources: [any DispatchSourceFileSystemObject]
    init(sources: [any DispatchSourceFileSystemObject]) { self.sources = sources }
    func cancel() { sources.forEach { $0.cancel() } }
}
