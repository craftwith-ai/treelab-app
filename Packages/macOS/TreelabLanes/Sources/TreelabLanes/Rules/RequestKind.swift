/// What a lane that waits for the user asks for, read from lab's `WHY=` and `WAITS_FOR=`.
public enum RequestKind: String, Sendable, CaseIterable {
    /// A question box or a question in the last message.
    case question
    /// A tool permission.
    case permission
    /// Work finished, to try together (acceptance).
    case toTry
    /// The lane is blocked and says why.
    case blocked
    /// The next step needs to be made clear.
    case toClarify
    /// A close waits for confirmation.
    case closing
    /// Anything else lab may add later.
    case other

    /// Reads the kind of a waiting lane.
    /// - Parameter lane: the lane read from lab.
    /// - Returns: the kind shown in the Feed.
    public static func of(_ lane: LaneRecord) -> RequestKind {
        let why = lane.why.lowercased()
        if why.hasPrefix("question waiting") { return .question }
        if why.hasPrefix("permission requested") { return .permission }
        if lane.waitsFor == "acceptance" || why.hasPrefix("work finished") { return .toTry }
        if why.hasPrefix("lane blocked") { return .blocked }
        if why.hasPrefix("next step to clarify") { return .toClarify }
        if why.hasPrefix("closing") { return .closing }
        return .other
    }
}
