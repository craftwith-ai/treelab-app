/// Why ``LabExecutableLocator`` refused a path.
public enum LabExecutableRefusal: String, Error, Sendable, Equatable {
    /// A relative path (it would depend on the current folder).
    case notAbsolute
    /// Nothing there.
    case missing
    /// Not a regular file.
    case notRegularFile
    /// Owned by another account than the user or root.
    case wrongOwner
    /// Writable by others.
    case writableByOthers
    /// Its folder is writable by others (the file could be replaced).
    case folderWritableByOthers
    /// Not executable.
    case notExecutable
}
