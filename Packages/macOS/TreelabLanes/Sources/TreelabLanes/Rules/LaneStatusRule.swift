/// Classifies a lane into a ``LaneStatus``.
///
/// t'attend = the tower's `FOR_YOU=yes`; hors compteur = a date or a permanent lane at rest;
/// travaille = a live session, or CI, merge, close or acceptance handled by the tower;
/// arrêtée = everything else (no session, nothing in progress).
public struct LaneStatusRule: Sendable {
    /// `WAITS_FOR=` values the tower handles without the user.
    public static let handledByTower: Set<String> = ["ci", "merge", "close", "acceptance"]

    /// Creates the rule.
    public init() {}

    /// The status of `lane`.
    /// - Parameter lane: the lane read from lab.
    /// - Returns: its place in the counter.
    public func status(of lane: LaneRecord) -> LaneStatus {
        if lane.forYou { return .waitingForYou }
        if lane.waitsFor == "date" { return .offCounter }
        if lane.permanent && !lane.sessionLive { return .offCounter }
        if lane.sessionLive { return .working }
        if Self.handledByTower.contains(lane.waitsFor) { return .working }
        return .stopped
    }
}
