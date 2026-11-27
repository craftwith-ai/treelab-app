/// Why the window cannot show lab's lanes, said on screen in plain words.
public enum LanesProblem: Error, Sendable, Equatable {
    /// No usable `lab` program was found.
    case labUnavailable(String)
    /// The snapshot was written by a lab version this build does not read.
    case unknownLabVersion(String)
    /// A file was refused by the safety checks (``SnapshotFileGate``).
    case refusedFile(path: String, reason: SnapshotFileRefusal)
    /// lab answered with an error.
    case labRefused(String)
}
