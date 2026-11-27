/// Where a folder sits among lab's projects: the project, and the lane when the folder is inside
/// one of its worktrees (`ROOT/.worktrees/<lane>`).
public struct LaneLocation: Sendable, Equatable {
    /// The project.
    public var project: ProjectLanes
    /// The lane, `nil` for the main checkout or a folder outside the lanes.
    public var lane: ClassifiedLane?

    /// Creates a location.
    /// - Parameters:
    ///   - project: the project.
    ///   - lane: the lane, if any.
    public init(project: ProjectLanes, lane: ClassifiedLane?) {
        self.project = project
        self.lane = lane
    }
}
