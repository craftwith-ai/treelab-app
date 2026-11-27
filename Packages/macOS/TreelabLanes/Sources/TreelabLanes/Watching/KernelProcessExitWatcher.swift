import Darwin
import Foundation

/// Watches process ends with the kernel (`DispatchSource` process sources): no polling.
public struct KernelProcessExitWatcher: ProcessExitWatching {
    /// Creates a watcher.
    public init() {}

    /// Watches `pids`.
    /// - Parameter pids: process identifiers.
    /// - Returns: each identifier once its process has ended.
    public func exits(of pids: [Int32]) -> AsyncStream<Int32> {
        AsyncStream { continuation in
            let queue = DispatchQueue(label: "sh.treelab.lanes.exits")
            // DispatchSource has no async-native replacement for process exits (carve-out).
            let sources = Set(pids).compactMap { pid -> (any DispatchSourceProcess)? in
                guard pid > 1 else { return nil }
                if kill(pid, 0) != 0 && errno == ESRCH {
                    continuation.yield(pid)
                    return nil
                }
                let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
                source.setEventHandler { continuation.yield(pid) }
                source.resume()
                return source
            }
            let holder = ProcessSourcesHolder(sources: sources)
            continuation.onTermination = { _ in holder.cancel() }
        }
    }
}

/// Keeps the process sources alive until the stream ends.
private final class ProcessSourcesHolder: Sendable {
    let sources: [any DispatchSourceProcess]
    init(sources: [any DispatchSourceProcess]) { self.sources = sources }
    func cancel() { sources.forEach { $0.cancel() } }
}
