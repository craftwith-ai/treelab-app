/// Builds a ``LanesSnapshot`` from projects and lanes: classification, indicators, counter, Feed order.
public struct LanesSnapshotBuilder: Sendable {
    private let rule: LaneStatusRule

    /// Creates a builder.
    /// - Parameter rule: the status rule, the accepted one by default.
    public init(rule: LaneStatusRule = LaneStatusRule()) {
        self.rule = rule
    }

    /// Builds the snapshot.
    /// - Parameters:
    ///   - projects: projects read from lab; a lane whose project is missing gets a project without a root.
    ///   - lanes: lanes read from lab.
    ///   - labVersion: lab's version.
    /// - Returns: projects by name, counter equal to the sum of their indicators, requests oldest first.
    public func snapshot(projects: [ProjectRecord], lanes: [LaneRecord], labVersion: String?) -> LanesSnapshot {
        var byProject: [String: ProjectRecord] = [:]
        for project in projects { byProject[project.project] = project }
        for lane in lanes where byProject[lane.project] == nil {
            byProject[lane.project] = ProjectRecord(project: lane.project, root: "")
        }
        let classified = lanes.map { lane -> ClassifiedLane in
            let status = rule.status(of: lane)
            return ClassifiedLane(record: lane, status: status, kind: status == .waitingForYou ? RequestKind.of(lane) : nil)
        }
        let grouped = Dictionary(grouping: classified, by: \.record.project)
        let entries = byProject.values
            .sorted { $0.project.localizedStandardCompare($1.project) == .orderedAscending }
            .map { project -> ProjectLanes in
                let lanes = (grouped[project.project] ?? [])
                    .sorted { $0.record.lane.localizedStandardCompare($1.record.lane) == .orderedAscending }
                var counts = StatusCounts()
                for lane in lanes { counts.add(lane.status) }
                return ProjectLanes(project: project, lanes: lanes, counts: counts)
            }
        let total = entries.reduce(StatusCounts()) { $0 + $1.counts }
        let requests = classified.filter { $0.status == .waitingForYou }.sorted(by: Self.olderFirst)
        return LanesSnapshot(projects: entries, total: total, requests: requests, labVersion: labVersion)
    }

    private static func olderFirst(_ lhs: ClassifiedLane, _ rhs: ClassifiedLane) -> Bool {
        switch (lhs.record.waitingSince, rhs.record.waitingSince) {
        case let (left?, right?) where left != right: return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        default: return lhs.id < rhs.id
        }
    }
}
