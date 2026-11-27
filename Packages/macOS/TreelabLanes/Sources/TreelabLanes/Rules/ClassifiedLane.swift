/// A lane with its place in the counter and, when it waits for the user, what it asks for.
public struct ClassifiedLane: Sendable, Equatable, Identifiable {
    /// The lane read from lab.
    public var record: LaneRecord
    /// Its place in the counter.
    public var status: LaneStatus
    /// What it asks for, only for ``LaneStatus/waitingForYou``.
    public var kind: RequestKind?

    /// `project/lane`.
    public var id: String { record.id }

    /// Creates a classified lane.
    /// - Parameters:
    ///   - record: the lane.
    ///   - status: its status.
    ///   - kind: its request kind when it waits for the user.
    public init(record: LaneRecord, status: LaneStatus, kind: RequestKind?) {
        self.record = record
        self.status = status
        self.kind = kind
    }
}
