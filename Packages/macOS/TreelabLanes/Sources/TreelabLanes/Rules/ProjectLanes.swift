/// A project with its classified lanes and its indicators.
public struct ProjectLanes: Sendable, Equatable, Identifiable {
    /// The project read from lab.
    public var project: ProjectRecord
    /// Its lanes, by name.
    public var lanes: [ClassifiedLane]
    /// Its indicators: lanes per status.
    public var counts: StatusCounts

    /// The project name.
    public var id: String { project.project }

    /// Creates a project entry.
    /// - Parameters:
    ///   - project: the project.
    ///   - lanes: its lanes.
    ///   - counts: its indicators.
    public init(project: ProjectRecord, lanes: [ClassifiedLane], counts: StatusCounts) {
        self.project = project
        self.lanes = lanes
        self.counts = counts
    }
}
