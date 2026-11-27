/// Yields the identifiers of processes as they end; the seam tests replace with a fake.
public protocol ProcessExitWatching: Sendable {
    /// Watches `pids` until the stream is dropped.
    /// - Parameter pids: process identifiers.
    /// - Returns: each identifier once its process has ended (at once for a process already gone).
    func exits(of pids: [Int32]) -> AsyncStream<Int32>
}
