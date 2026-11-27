/// Finds which project and lane a folder (a workspace's or a terminal's) belongs to.
///
/// Matching is by path only, never by name: a workspace named like a project but elsewhere
/// gets no indicator, so the window never shows a figure for the wrong project.
public struct LaneLocator: Sendable {
    /// Creates a locator.
    public init() {}

    /// The location of `directory`.
    /// - Parameters:
    ///   - directory: an absolute folder path.
    ///   - snapshot: the current snapshot.
    /// - Returns: the deepest project root containing it, with its lane; `nil` outside every project.
    public func locate(directory: String, in snapshot: LanesSnapshot) -> LaneLocation? {
        let path = Self.normalized(directory)
        guard path.hasPrefix("/") else { return nil }
        let best = snapshot.projects
            .filter { !$0.project.root.isEmpty }
            .filter { path == Self.normalized($0.project.root) || path.hasPrefix(Self.normalized($0.project.root) + "/") }
            .max { Self.normalized($0.project.root).count < Self.normalized($1.project.root).count }
        guard let project = best else { return nil }
        let lanesPrefix = Self.normalized(project.project.root) + "/.worktrees/"
        guard path.hasPrefix(lanesPrefix) else { return LaneLocation(project: project, lane: nil) }
        let laneName = path.dropFirst(lanesPrefix.count).split(separator: "/").first.map(String.init) ?? ""
        return LaneLocation(project: project, lane: project.lanes.first { $0.record.lane == laneName })
    }

    private static func normalized(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1 && trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }
}
