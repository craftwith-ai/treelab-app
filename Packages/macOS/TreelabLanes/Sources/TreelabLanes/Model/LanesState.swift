/// What the window shows at a given moment: the snapshot, or why it cannot be read.
public struct LanesState: Sendable, Equatable {
    /// The last snapshot read (empty before the first read).
    public var snapshot: LanesSnapshot
    /// Why lab's lanes cannot be shown or trusted, said on screen; `nil` when all is well.
    public var problem: LanesProblem?
    /// Files refused by the safety checks, with the reason; their lanes are left out.
    public var refusedFiles: [String: SnapshotFileRefusal]
    /// Whether a first read finished.
    public var loaded: Bool

    /// Creates a state, empty by default.
    /// - Parameters:
    ///   - snapshot: the snapshot.
    ///   - problem: the problem, if any.
    ///   - refusedFiles: refused files.
    ///   - loaded: a first read finished.
    public init(snapshot: LanesSnapshot = .empty, problem: LanesProblem? = nil, refusedFiles: [String: SnapshotFileRefusal] = [:], loaded: Bool = false) {
        self.snapshot = snapshot
        self.problem = problem
        self.refusedFiles = refusedFiles
        self.loaded = loaded
    }
}
