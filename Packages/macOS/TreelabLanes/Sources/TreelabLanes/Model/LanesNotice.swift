/// The outcome of the user's last action in the Feed, shown in one line.
public enum LanesNotice: Sendable, Equatable {
    /// The answer reached the lane `id`.
    case sent(String)
    /// A relaunch was asked for these lanes.
    case relaunched([String])
    /// The lane `id` was brought to the front.
    case opened(String)
    /// lab refused; nothing else was done.
    case refused(String)
}
