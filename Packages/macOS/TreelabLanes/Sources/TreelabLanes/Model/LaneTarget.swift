/// A project, or one lane of it, that a targeted `lab app snapshot` rewrites.
public struct LaneTarget: Sendable, Hashable {
    /// The project.
    public var project: String
    /// The lane, `nil` for the project file.
    public var lane: String?

    /// Creates a target.
    /// - Parameters:
    ///   - project: the project.
    ///   - lane: the lane, `nil` for the project.
    public init(project: String, lane: String?) {
        self.project = project
        self.lane = lane
    }

    /// The snapshot command for this target, `nil` when a name is not safe.
    /// - Parameter readerPID: Treelab's process id.
    /// - Returns: `lab app snapshot --reader <pid> <project> [<lane>]`.
    public func command(readerPID: Int32) -> LabCommand? {
        guard let project = LabName(project) else { return nil }
        if let lane {
            guard let laneName = LabName(lane) else { return nil }
            return .snapshot(readerPID: readerPID, project: project, lane: laneName)
        }
        return .snapshot(readerPID: readerPID, project: project, lane: nil)
    }
}
