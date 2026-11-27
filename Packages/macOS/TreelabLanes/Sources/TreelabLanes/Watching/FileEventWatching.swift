/// Yields the paths that changed under some folders; the seam tests replace with a scripted fake.
public protocol FileEventWatching: Sendable {
    /// Watches `paths` (files or folders, recursively) until the stream is dropped.
    /// - Parameter paths: absolute paths.
    /// - Returns: batches of changed paths.
    func changes(under paths: [String]) -> AsyncStream<[String]>
}
