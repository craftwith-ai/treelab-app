/// How many lanes are in each ``LaneStatus``.
public struct StatusCounts: Sendable, Equatable {
    /// Lanes waiting for the user.
    public var waitingForYou: Int
    /// Lanes moving on without the user.
    public var working: Int
    /// Lanes to relaunch.
    public var stopped: Int
    /// Lanes outside the counter.
    public var offCounter: Int

    /// Creates counts, zero by default.
    /// - Parameters:
    ///   - waitingForYou: lanes waiting for the user.
    ///   - working: lanes moving on.
    ///   - stopped: lanes to relaunch.
    ///   - offCounter: lanes outside the counter.
    public init(waitingForYou: Int = 0, working: Int = 0, stopped: Int = 0, offCounter: Int = 0) {
        self.waitingForYou = waitingForYou
        self.working = working
        self.stopped = stopped
        self.offCounter = offCounter
    }

    /// Lanes inside the counter: waiting, working and stopped (the sum of the indicators).
    public var counted: Int { waitingForYou + working + stopped }

    /// Adds one lane of `status`.
    /// - Parameter status: the lane's status.
    public mutating func add(_ status: LaneStatus) {
        switch status {
        case .waitingForYou: waitingForYou += 1
        case .working: working += 1
        case .stopped: stopped += 1
        case .offCounter: offCounter += 1
        }
    }

    /// The sum of two counts.
    public static func + (lhs: StatusCounts, rhs: StatusCounts) -> StatusCounts {
        StatusCounts(
            waitingForYou: lhs.waitingForYou + rhs.waitingForYou,
            working: lhs.working + rhs.working,
            stopped: lhs.stopped + rhs.stopped,
            offCounter: lhs.offCounter + rhs.offCounter
        )
    }
}
