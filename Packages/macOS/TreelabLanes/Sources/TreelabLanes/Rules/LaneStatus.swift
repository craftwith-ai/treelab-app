/// Where a lane stands for the user, the rule of the accepted mock-ups (batches 05 to 08).
public enum LaneStatus: String, Sendable, CaseIterable {
    /// The user must act: a question, a permission, a trial (`FOR_YOU=yes`).
    case waitingForYou
    /// The lane moves on without the user: a live session, or CI, merge, close handled by the tower.
    case working
    /// Nothing runs and nothing is awaited: the lane needs a relaunch.
    case stopped
    /// Outside the counter: waiting for a date, or a permanent lane at rest; never relaunched from here.
    case offCounter
}
