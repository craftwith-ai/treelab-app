/// Everything the window and the Feed show, computed from what lab wrote.
public struct LanesSnapshot: Sendable, Equatable {
    /// Projects by name, each with its lanes and indicators.
    public var projects: [ProjectLanes]
    /// The counter: the sum of every project's indicators.
    public var total: StatusCounts
    /// Lanes waiting for the user, oldest wait first (unknown dates last, then by name).
    public var requests: [ClassifiedLane]
    /// The lab version that wrote the files.
    public var labVersion: String?

    /// An empty snapshot (nothing read yet).
    public static let empty = LanesSnapshot(projects: [], total: StatusCounts(), requests: [], labVersion: nil)

    /// Creates a snapshot.
    /// - Parameters:
    ///   - projects: projects with their lanes.
    ///   - total: the counter.
    ///   - requests: waiting lanes in Feed order.
    ///   - labVersion: lab's version.
    public init(projects: [ProjectLanes], total: StatusCounts, requests: [ClassifiedLane], labVersion: String?) {
        self.projects = projects
        self.total = total
        self.requests = requests
        self.labVersion = labVersion
    }

    /// Every lane of `status`, by project then lane name.
    /// - Parameter status: the status to keep.
    /// - Returns: the lanes.
    public func lanes(_ status: LaneStatus) -> [ClassifiedLane] {
        projects.flatMap { $0.lanes.filter { $0.status == status } }
    }
}
