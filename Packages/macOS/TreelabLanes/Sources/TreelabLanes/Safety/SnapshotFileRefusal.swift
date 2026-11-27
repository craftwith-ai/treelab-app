/// Why ``SnapshotFileGate`` refused a file.
public enum SnapshotFileRefusal: String, Error, Sendable, Equatable {
    /// The path leaves the folder it must stay in.
    case outsideFolder
    /// The path is a symbolic link (followed links could lead anywhere).
    case symbolicLink
    /// Not a regular file (a folder, a pipe, a device).
    case notRegularFile
    /// The file or its folder belongs to someone else.
    case wrongOwner
    /// Someone other than its owner may write it.
    case writableByOthers
    /// Larger than the ceiling (lab's files are small).
    case tooLarge
    /// Missing.
    case missing
    /// Unreadable for another reason.
    case unreadable
}
